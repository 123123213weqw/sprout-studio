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

    let engine = RealtimeEngine()
    private var displayTimer: Timer?

    static func defaultSamplesRoot() -> URL? {
        let url = URL(fileURLWithPath: "/Users/wangyue/ZCodeProject/sprout-media/app/dist/samples")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    var projectName: String { project?["name"]?.asString ?? "未打开工程" }
    var tracks: [JSONObject] { (project?["tracks"]?.asArray ?? []).compactMap(\.asObject) }

    func open(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let validated = try validateProject(try loadSprout(text: text))
            project = validated
            projectURL = url
            totalBeats = jnum(validated, "bars", 4) * 4
            try engine.load(project: validated, samplesRoot: samplesRoot)
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
                if model.busy { ProgressView().scaleEffect(0.6) }
                Button("导出 WAV") { model.exportWAV() }.disabled(model.project == nil)
                Button("导出 MIDI") { model.exportMIDI() }.DisabledStyle(disabled: model.project == nil)
            }
            .padding(12)

            if let err = model.error {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal, 12)
            }

            Divider()

            if let p = model.project {
                VStack(alignment: .leading, spacing: 0) {
                    // 走拍条
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                            RoundedRectangle(cornerRadius: 3).fill(Color.accentColor)
                                .frame(width: max(0, min(1, model.beat / max(model.totalBeats, 1))) * geo.size.width)
                            Rectangle().fill(.red).frame(width: 2)
                                .offset(x: min(geo.size.width - 2, max(0, model.beat / max(model.totalBeats, 1)) * geo.size.width))
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    Text(String(format: "%.1f / %.0f 拍", model.beat, model.totalBeats))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                List(0..<model.tracks.count, id: \.self) { index in
                    TrackRow(model: model, track: model.tracks[index])
                }
                .listStyle(.inset)
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
        .frame(minWidth: 680, minHeight: 420)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = PlayerModel()
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
