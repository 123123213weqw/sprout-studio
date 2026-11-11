// 音源浏览器 + 音色编辑:
//   SourceBrowser —— 179 个采样 preset(按 录音/音色库/合成 分类,只列当前音源兼容项)
//                    + 纯合成选项;行内试听;
//   SoundInspector —— 采样参数(gain/release/cutoff)或合成音色参数(按字段规格
//                    动态生成)+ 波形 + 三个快捷预设(soft/clear/short)。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit
import SproutAudio
import SproutRealtime

struct PresetRowInfo {
    let id: String
    let name: String
    let category: String // 录音采样 / 音色库 / 合成采样
}

struct SourceBrowser: View {
    @ObservedObject var model: PlayerModel
    let track: JSONObject
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private let instrument: String
    private let kind: String

    init(model: PlayerModel, track: JSONObject) {
        self.model = model
        self.track = track
        self.instrument = track["instrument"]?.asString ?? "lead"
        self.kind = track["kind"]?.asString ?? "tonal"
    }

    private var presets: [PresetRowInfo] {
        var out: [PresetRowInfo] = []
        let compatible = Samples.shared.presets.values
            .filter { $0.instrument == instrument }
            .sorted { $0.name < $1.name }
        for preset in compatible {
            let category: String
            if preset.id.hasPrefix("vsco-") || preset.id.hasPrefix("karoryfer-") {
                category = "真实录音"
            } else if preset.id.hasPrefix("fluid-") {
                category = "音色库(GM)"
            } else {
                category = "合成采样"
            }
            out.append(PresetRowInfo(id: preset.id, name: preset.name, category: category))
        }
        return out
    }

    private var filtered: [PresetRowInfo] {
        guard !search.isEmpty else { return presets }
        return presets.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择音源 · \(Tables.shared.instruments[instrument]?.name ?? instrument)")
                    .font(.title3.bold())
                Spacer()
                TextField("搜索", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("完成") { dismiss() }
            }
            .padding(12)
            List {
                Section("合成音源(无采样)") {
                    Button {
                        model.setTrackSampler(trackId: trackId, presetId: nil)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "waveform")
                            Text("内置合成音色(可在音色编辑里调参数)")
                            Spacer()
                        }
                    }
                }
                let grouped = Dictionary(grouping: filtered, by: \.category)
                ForEach(["真实录音", "音色库(GM)", "合成采样"], id: \.self) { category in
                    if let items = grouped[category], !items.isEmpty {
                        Section("\(category)(\(items.count))") {
                            ForEach(items, id: \.id) { preset in
                                presetRow(preset)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var trackId: String { track["id"]?.asString ?? "" }

    private func presetRow(_ preset: PresetRowInfo) -> some View {
        let isCurrent = track["sampler"]?.asObject?["preset"]?.asString == preset.id
        return HStack {
            Text(preset.name)
                .font(.body.weight(isCurrent ? .semibold : .regular))
            if isCurrent { Text("当前").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.accentColor.opacity(0.2))) }
            Spacer()
            Button {
                var settings = JSONObject()
                settings["preset"] = .string(preset.id)
                try? model.engine.previewNote(
                    instrument: instrument,
                    pitch: kind == "drum" ? (Tables.shared.instruments[instrument]?.pitch ?? 36) : 64,
                    sound: track["sound"], sampler: .object(settings)
                )
            } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .help("试听")
            Button("使用") {
                model.setTrackSampler(trackId: trackId, presetId: preset.id)
                dismiss()
            }
            .disabled(isCurrent)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - 音色编辑

struct SoundInspector: View {
    @ObservedObject var model: PlayerModel
    let track: JSONObject
    @Environment(\.dismiss) private var dismiss
    @State private var showBrowser = false

    private let instrument: String
    init(model: PlayerModel, track: JSONObject) {
        self.model = model
        self.track = track
        self.instrument = track["instrument"]?.asString ?? "lead"
    }

    private var trackId: String { track["id"]?.asString ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("音色 · \(track["name"]?.asString ?? instrument)").font(.title3.bold())
                Spacer()
                Button("收藏此音色") { model.saveSoundFavorite(trackId: trackId) }
                Button("换音源…") { showBrowser = true }
                Button("关闭") { dismiss() }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let sampler = track["sampler"]?.asObject {
                        Text("采样参数").font(.headline)
                        samplerSlider("音量增益", key: "gain", range: 0.05...1.5, format: "%.2f", sampler: sampler)
                        samplerSlider("释放尾音", key: "release", range: 0.02...2, format: "%.2f 秒", sampler: sampler)
                        samplerSlider("低通亮度", key: "cutoff", range: 200...18000, format: "%.0f Hz", sampler: sampler)
                    } else if let sound = track["sound"]?.asObject {
                        Text("合成音色").font(.headline)
                        ForEach(Tables.shared.soundDefinitions[instrument]?.fields ?? [], id: \.key) { field in
                            soundSlider(field, sound: sound)
                        }
                        if Tables.shared.soundDefinitions[instrument]?.kind == "tonal" {
                            Picker("波形", selection: Binding(
                                get: { sound["waveform"]?.asString ?? "native" },
                                set: { model.updateTrackSound(trackId: trackId, key: "waveform", value: .string($0)) }
                            )) {
                                ForEach(["native", "sine", "triangle", "sawtooth", "square"], id: \.self) { Text($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 340)
                        }
                        HStack(spacing: 8) {
                            ForEach(soundPresetIds, id: \.self) { id in
                                Button(["soft": "柔和", "clear": "清晰", "short": "短促"][id] ?? id) {
                                    model.applySoundPreset(trackId: trackId, presetId: id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        Text("这条轨道使用默认合成参数;换音源后可调采样,或在下方试听当前音色。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.soundFavorites.isEmpty {
                        Text("收藏(\(model.soundFavorites.count)/32,跨工程)").font(.headline)
                        ForEach(0..<model.soundFavorites.count, id: \.self) { index in
                            let fav = model.soundFavorites[index]
                            HStack {
                                Circle().fill(Color(nsColor: .systemBlue)).frame(width: 8, height: 8)
                                Text(fav["name"]?.asString ?? "").font(.body)
                                Text(fav["instrument"]?.asString ?? "").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("应用") { model.applySoundFavorite(fav, toTrack: trackId) }
                                    .buttonStyle(.bordered)
                                Button {
                                    model.soundFavorites.remove(at: index)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    Button {
                        try? model.engine.previewNote(
                            instrument: instrument,
                            pitch: (Tables.shared.instruments[instrument]?.kind == "drum")
                                ? (Tables.shared.instruments[instrument]?.pitch ?? 36) : 64,
                            sound: track["sound"], sampler: track["sampler"]
                        )
                    } label: { Label("试听一个音", systemImage: "play.circle") }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 430, minHeight: 420)
        .sheet(isPresented: $showBrowser) {
            SourceBrowser(model: model, track: track)
        }
    }

    private func soundSlider(_ field: SoundFieldSpec, sound: JSONObject) -> some View {
        HStack(spacing: 10) {
            Text("\(field.label)(\(field.min)–\(field.max))").font(.caption).frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { jnum(sound, field.key, (field.min + field.max) / 2) },
                set: { model.updateTrackSound(trackId: trackId, key: field.key, value: .number($0)) }
            ), in: field.min...field.max)
            .frame(maxWidth: 320)
        }
    }

    private func samplerSlider(_ label: String, key: String, range: ClosedRange<Double>, format: String, sampler: JSONObject) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).frame(width: 150, alignment: .leading)
            Slider(value: Binding(
                get: { jnum(sampler, key, range.lowerBound) },
                set: { model.updateTrackSamplerField(trackId: trackId, key: key, value: .number($0)) }
            ), in: range)
            .frame(maxWidth: 320)
            Text(String(format: format, jnum(sampler, key))).font(.caption.monospacedDigit()).frame(width: 64, alignment: .trailing)
        }
    }
}
#endif
