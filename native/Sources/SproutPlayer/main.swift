// Sprout Player:macOS 原生播放器壳(SwiftUI + AppKit 引导)。
// M2 第一切片:打开 .sprout、实时播放、轨道混音、导出 WAV/MIDI。
// canImport 守卫:Linux 上仅打印提示,保持 SwiftPM 全平台可构建。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit
import SproutAudio
import SproutRealtime

// MARK: - 模型

final class PlayerModel: ObservableObject {
    @Published var project: JSONObject?
    @Published var projectURL: URL?
    @Published var playing = false
    @Published var beat: Double = 0
    @Published var totalBeats: Double = 16
    @Published var error: String?
    @Published var busy = false
    @Published var samplesRoot: URL? = defaultSamplesRoot()
    @Published var rollEvents: [RollEvent] = []
    @Published var selectedNoteId: String?

    func deleteSelectedNote() {
        guard let id = selectedNoteId else { return }
        deleteNote(id: id)
        selectedNoteId = nil
    }

    let engine = RealtimeEngine()
    private var displayTimer: Timer?

    static func defaultSamplesRoot() -> URL? {
        let url = URL(fileURLWithPath: "/Users/wangyue/ZCodeProject/sprout-media/app/dist/samples")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    var projectName: String { project?["name"]?.asString ?? "未打开工程" }
    var tracks: [JSONObject] { (project?["tracks"]?.asArray ?? []).compactMap(\.asObject) }

    private func rollEventsContains(_ id: String) -> Bool {
        // 选中有效性在重建后校验:音符可能被共享 Pattern 物化为 link_ id
        rollEvents.contains { $0.noteId == id }
    }

    func open(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let validated = try validateProject(try loadSprout(text: text))
            project = validated
            projectURL = url
            totalBeats = jnum(validated, "bars", 4) * 4
            try engine.load(project: validated, samplesRoot: samplesRoot)
            rebuildRoll()
            beat = 0
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    func togglePlay() {
        if engine.playing {
            engine.stop()
        } else {
            do { try engine.play() } catch { self.error = "\(error)" }
        }
        syncTransport()
    }

    func stopPlay() {
        engine.stop()
        syncTransport()
    }

    func syncTransport() {
        playing = engine.playing
    }

    /// 卷帘事件 = 播放计划事件(与音频调度同源)。
    func rebuildRoll() {
        guard let p = project, let plan = try? playbackPlan(p, range: .null) else {
            rollEvents = []
            return
        }

        let list = (p["tracks"]?.asArray ?? []).compactMap(\.asObject)
        rollEvents = plan.events.compactMap { e in
            guard e.trackIndex < list.count else { return nil }
            let t = list[e.trackIndex]
            return RollEvent(
                noteId: e.noteId,
                trackId: t["id"]?.asString ?? "",
                beat: e.beat, duration: e.duration, pitch: e.pitch, velocity: e.velocity,
                colorHex: t["color"]?.asString ?? "#888888",
                instrument: t["instrument"]?.asString ?? "lead",
                kind: t["kind"]?.asString ?? "tonal"
            )
        }
        if let id = selectedNoteId, !rollEvents.contains(where: { $0.noteId == id }) {
            selectedNoteId = nil
        }
    }

    func seek(to beat: Double) {
        engine.seek(to: beat)
        self.beat = engine.currentBeat
    }

    // MARK: - 编辑(整工程快照撤销)

    let undoManager = UndoManager()
    @Published var canUndoRedo = (false, false)

    private func refreshUndoState() {
        canUndoRedo = (undoManager.canUndo, undoManager.canRedo)
    }

    private func adopt(_ json: String) {
        do {
            let validated = try validateProject(try loadSprout(text: json))
            project = validated
            let wasPlaying = engine.playing
            let position = engine.currentBeat
            try engine.load(project: validated, samplesRoot: samplesRoot)
            if wasPlaying {
                try engine.play(from: position)
            } else {
                engine.seek(to: position)
            }
            rebuildRoll()
            refreshUndoState()
        } catch {
            self.error = "\(error)"
        }
    }

    /// 编辑入口:快照 → 修改 → 校验通过才采纳;失败保持原状。
    func applyEdit(_ label: String, _ mutate: (JSONObject) -> JSONObject) {
        guard let p = project else { return }
        let oldJSON = serializeProject(p)
        let next = mutate(p)
        do {
            _ = try validateProject(.object(next)) // 先验,失败不动
        } catch {
            self.error = "\(error)"
            return
        }
        let newJSON = serializeProject(next)
        adopt(newJSON)
        undoManager.registerUndo(withTarget: self) { target in
            target.swapBack(to: oldJSON, from: newJSON)
        }
        undoManager.setActionName(label)
        refreshUndoState()
    }

    private func swapBack(to oldJSON: String, from newJSON: String) {
        adopt(oldJSON)
        undoManager.registerUndo(withTarget: self) { target in
            target.swapBack(to: newJSON, from: oldJSON)
        }
        refreshUndoState()
    }

    func undo() { undoManager.undo(); refreshUndoState() }
    func redo() { undoManager.redo(); refreshUndoState() }

    // MARK: - 音符操作

    private func noteTrack(id: String) -> (Int, Int)? {
        guard let p = project else { return nil }
        let list = (p["tracks"]?.asArray ?? [])
        for ti in list.indices {
            guard let t = list[ti].asObject else { continue }
            let notes = t["notes"]?.asArray ?? []
            for ni in notes.indices where notes[ni].asObject?["id"]?.asString == id {
                return (ti, ni)
            }
        }
        return nil
    }

    func updateNote(id: String, label: String, start: Double? = nil, pitch: Double? = nil, duration: Double? = nil) {
        applyEdit(label) { p in
            var next = p
            var list = (next["tracks"]?.asArray ?? [])
            for ti in list.indices {
                guard var t = list[ti].asObject else { continue }
                var notes = t["notes"]?.asArray ?? []
                for ni in notes.indices {
                    guard var n = notes[ni].asObject, n["id"]?.asString == id else { continue }
                    if let s = start { n["start"] = .number(s) }
                    if let p2 = pitch { n["pitch"] = .number(p2) }
                    if let d = duration { n["duration"] = .number(d) }
                    notes[ni] = .object(n)
                }
                t["notes"] = .array(notes)
                list[ti] = .object(t)
            }
            next["tracks"] = .array(list)
            return next
        }
    }

    func deleteNote(id: String) {
        applyEdit("删除音符") { p in
            var next = p
            var list = (next["tracks"]?.asArray ?? [])
            for ti in list.indices {
                guard var t = list[ti].asObject else { continue }
                let notes = t["notes"]?.asArray ?? []
                t["notes"] = .array(notes.filter { $0.asObject?["id"]?.asString != id })
                list[ti] = .object(t)
            }
            next["tracks"] = .array(list)
            return next
        }
    }

    func createNote(trackId: String, beat: Double, pitch: Double, isDrum: Bool) {
        applyEdit("新建音符") { p in
            var next = p
            var list = (next["tracks"]?.asArray ?? [])
            for ti in list.indices {
                guard var t = list[ti].asObject else { continue }
                guard t["id"]?.asString == trackId else { continue }
                var n = JSONObject()
                n["id"] = .string(jsUid())
                n["pitch"] = .number(pitch)
                n["start"] = .number(beat)
                n["duration"] = .number(isDrum ? 0.25 : 0.5)
                n["velocity"] = .number(96)
                var notes = t["notes"]?.asArray ?? []
                notes.append(.object(n))
                t["notes"] = .array(notes)
                list[ti] = .object(t)
            }
            next["tracks"] = .array(list)
            return next
        }
    }

    func startDisplay() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.beat = self.engine.currentBeat
            self.playing = self.engine.playing
        }
    }

    /// 轨道属性就地修改并热应用(混音不触发重装载)。
    func updateTrack(id: String, key: String, value: JSONValue) {
        guard var p = project else { return }
        var list: [JSONValue] = []
        for element in (p["tracks"]?.asArray ?? []) {
            if var obj = element.asObject, obj["id"]?.asString == id {
                obj[key] = value
                list.append(.object(obj))
            } else {
                list.append(element)
            }
        }
        p["tracks"] = .array(list)
        project = p
        engine.applyMix()
    }

    func trackFlag(_ track: JSONObject, _ key: String) -> Bool {
        track[key]?.asBool == true
    }

    func exportWAV() {
        guard let p = project else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = (projectName.isEmpty ? "export" : projectName) + ".wav"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.busy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let (wav, stats) = try renderWAV(p, options: RenderOptions(samplesRoot: self?.samplesRoot))
                    try Data(wav).write(to: url)
                    DispatchQueue.main.async {
                        self?.busy = false
                        self?.error = stats.nonSilent ? nil : "导出完成,但输出接近静音"
                    }
                } catch {
                    DispatchQueue.main.async { self?.error = "导出失败:\(error)"; self?.busy = false }
                }
            }
        }
    }

    func exportMIDI() {
        guard let p = project else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (projectName.isEmpty ? "export" : projectName) + ".mid"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let bytes = try encodeMIDI(p)
                try Data(bytes).write(to: url)
            } catch {
                DispatchQueue.main.async { self?.error = "导出失败:\(error)" }
            }
        }
    }

    func chooseSamplesRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择采样目录(包含 vsco/、edm/ 等子目录,来自 release zip 的 dist/samples)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            self.samplesRoot = url
            if let p = self.project {
                try? self.engine.load(project: p, samplesRoot: url)
            }
        }
    }
}

// MARK: - 视图

struct TrackRow: View {
    @ObservedObject var model: PlayerModel
    let track: JSONObject

    var body: some View {
        let id = track["id"]?.asString ?? ""
        let color = Color(nsColor: NSColor(hex: track["color"]?.asString ?? "#888888") ?? .gray)
        let instrument = track["instrument"]?.asString ?? ""
        let noteCount = track["notes"]?.asArray?.count ?? 0
        return HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(track["name"]?.asString ?? instrument).font(.body.weight(.medium))
                Text("\(instrument) · \(noteCount) 音符").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("独奏") { model.updateTrack(id: id, key: "solo", value: .bool(!model.trackFlag(track, "solo"))) }
                .buttonStyle(.bordered)
                .tint(model.trackFlag(track, "solo") ? .accentColor : .secondary)
            Button("静音") { model.updateTrack(id: id, key: "muted", value: .bool(!model.trackFlag(track, "muted"))) }
                .buttonStyle(.bordered)
                .tint(model.trackFlag(track, "muted") ? .red : .secondary)
            Slider(value: Binding(
                get: { jnum(track, "volume", 0.7) },
                set: { model.updateTrack(id: id, key: "volume", value: .number($0)) }
            ), in: 0...1)
            .frame(width: 130)
        }
        .padding(.vertical, 2)
    }
}

struct ContentView: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { model.open(url: url) }
                } label: {
                    Label("打开", systemImage: "folder")
                }
                Button {
                    model.togglePlay()
                } label: {
                    Label(model.playing ? "停止" : "播放", systemImage: model.playing ? "stop.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.project == nil)
                Text(model.projectName)
                    .font(.headline)
                Text(model.project.map { p in
                    "\(p["style"]?.asString ?? "") · \(p["key"]?.asString ?? "") · \(Int(jnum(p, "bpm", 120))) BPM · \(Int(jnum(p, "bars", 4))) 小节"
                } ?? "未打开工程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndoRedo.0)
                Button { model.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                    .disabled(!model.canUndoRedo.1)
                if model.busy { ProgressView().scaleEffect(0.6) }
                Button("导出 WAV") { model.exportWAV() }.disabled(model.project == nil)
                Button("导出 MIDI") { model.exportMIDI() }.DisabledStyle(disabled: model.project == nil)
            }
            .padding(12)

            if let err = model.error {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 12)
            }

            Divider()

            if model.project != nil {
                HStack(spacing: 0) {
                    // 轨道侧栏
                    List(0..<model.tracks.count, id: \.self) { index in
                        TrackRow(model: model, track: model.tracks[index])
                    }
                    .listStyle(.sidebar)
                    .frame(width: 268)
                    Divider()
                    // 主区:走拍条 + 卷帘
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
                                    .frame(width: max(0, min(1, model.beat / max(model.totalBeats, 1))) * geo.size.width)
                            }
                        }
                        .frame(height: 7)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        Text(String(format: "%.1f / %.0f 拍 · 点击卷帘定位", model.beat, model.totalBeats))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        RollView(model: model)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "music.note.house").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("打开一个 .sprout 工程开始播放").foregroundStyle(.secondary)
                    if model.samplesRoot == nil {
                        Text("未找到采样目录:含采样音源的工程将回退为合成音色。可从菜单选择采样目录。")
                            .font(.caption).foregroundStyle(.orange)
                            .frame(maxWidth: 420)
                    }
                }
                Spacer()
            }
        }
        .frame(minWidth: 1020, minHeight: 560)
        .onAppear { model.startDisplay() }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value: UInt64 = 0
        guard let first = hex.first, first == "#", hex.count == 7,
              Scanner(string: String(hex.dropFirst())).scanHexInt64(&value) else { return nil }
        self.init(red: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

struct DisabledModifier: ViewModifier {
    let disabled: Bool
    func body(content: Content) -> some View {
        if disabled { content.disabled(true) } else { content }
    }
}

extension View {
    func DisabledStyle(disabled: Bool) -> some View { modifier(DisabledModifier(disabled: disabled)) }
}

// MARK: - AppKit 引导(SwiftPM 可执行目标)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var playerModel: PlayerModel?
    var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PlayerModel()
        playerModel = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Delete / Fn-Delete 删除选中音符
            if event.keyCode == 51 || event.keyCode == 117, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self?.playerModel?.deleteSelectedNote()
                return nil
            }
            return event
        }
        let arguments = CommandLine.arguments
        if arguments.count > 1 {
            model.open(url: URL(fileURLWithPath: arguments[1]))
        }
        let content = NSHostingView(rootView: ContentView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Sprout Player"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.regular)
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.activate(ignoringOtherApps: true)
NSApplication.shared.run()
#else
print("Sprout Player 需要 macOS(AppKit)。")
#endif
