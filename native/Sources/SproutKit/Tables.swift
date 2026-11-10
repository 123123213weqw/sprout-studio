// shared/tables.json 的加载器。SproutKit 内不允许出现第二份手抄表;
// 唯一数据源是 shared/tables.json,由 tools/sync-shared.mjs 同步为包资源。

import Foundation

public struct StyleInfo: Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let desc: String
    public let bpm: Double
}

public struct SproutError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public struct InstrumentMeta {
    public let name: String
    public let label: String
    public let kind: String
    public let icon: String
    public let color: String
    public let pitch: Int? // 仅鼓件有
}

public struct KeyInfo {
    public let root: Double
    public let scale: [Double]
    public let mode: String
}

public struct SoundFieldSpec {
    public let key: String
    public let min: Double
    public let max: Double
    public let label: String
    public let unit: String
}

public struct SoundDefinition {
    public let kind: String
    public let fields: [SoundFieldSpec]
}

public struct SamplePresetInfo {
    public let instrument: String
    public let kind: String
    public let gain: Double
    public let release: Double
}

public enum Tables {
    public static let shared: TablesData = load()

    public struct TablesData {
        public let instruments: [String: InstrumentMeta]
        public let keys: [String: KeyInfo]
        public let styleIds: Set<String>
        public let styles: [StyleInfo]
        public let sectionKinds: Set<String>
        public let waveforms: Set<String>
        public let soundDefaults: [String: JSONObject]     // 键序 = JS 字面量序,normalizeSound 依赖
        public let soundDefinitions: [String: SoundDefinition]
        public let controlDefaults: JSONObject             // 键序 = CONTROL_DEFAULTS 序
        public let barLengths: [Double]
        public let maxBars: Int
        public let maxBeats: Double
        public let maxProjectNotes: Int
        public let patternLimits: (patterns: Int, notes: Int, perPattern: Int)
        public let samplePresets: [String: SamplePresetInfo]
    }

    static func load() -> TablesData {
        guard let url = Bundle.module.url(forResource: "tables", withExtension: "json"),
              let text = try? String(contentsOfFile: url.path, encoding: .utf8),
              let value = try? parseJSON(text),
              let root = value.asObject else {
            fatalError("shared/tables.json 缺失或损坏:先运行 node tools/sync-shared.mjs")
        }

        var instruments: [String: InstrumentMeta] = [:]
        if let objs = root["instruments"]?.asObject {
            for (id, v) in objs.pairs {
                guard let o = v.asObject else { continue }
                instruments[id] = InstrumentMeta(
                    name: o["name"]?.asString ?? "",
                    label: o["label"]?.asString ?? "",
                    kind: o["kind"]?.asString ?? "",
                    icon: o["icon"]?.asString ?? "",
                    color: o["color"]?.asString ?? "",
                    pitch: o["pitch"]?.asNumber.map(Int.init)
                )
            }
        }

        var keys: [String: KeyInfo] = [:]
        if let objs = root["keys"]?.asObject {
            for (name, v) in objs.pairs {
                guard let o = v.asObject else { continue }
                keys[name] = KeyInfo(
                    root: jnum(o, "root", 60),
                    scale: (o["scale"]?.asArray ?? []).compactMap { $0.asNumber },
                    mode: o["mode"]?.asString ?? "major"
                )
            }
        }

        var soundDefaults: [String: JSONObject] = [:]
        if let defaults = root["sound"]?.asObject?["defaults"]?.asObject {
            for (instrument, v) in defaults.pairs {
                if let o = v.asObject { soundDefaults[instrument] = o }
            }
        }

        var soundDefinitions: [String: SoundDefinition] = [:]
        if let defs = root["sound"]?.asObject?["definitions"]?.asObject {
            for (instrument, v) in defs.pairs {
                guard let o = v.asObject, let fields = o["fields"]?.asArray else { continue }
                soundDefinitions[instrument] = SoundDefinition(
                    kind: o["kind"]?.asString ?? "tonal",
                    fields: fields.compactMap { fv in
                        guard let f = fv.asObject, let key = f["key"]?.asString,
                              let min = f["min"]?.asNumber, let max = f["max"]?.asNumber else { return nil }
                        return SoundFieldSpec(key: key, min: min, max: max,
                                              label: f["label"]?.asString ?? key,
                                              unit: f["unit"]?.asString ?? "")
                    }
                )
            }
        }

        var presets: [String: SamplePresetInfo] = [:]
        if let list = root["samplePresets"]?.asArray {
            for pv in list {
                guard let o = pv.asObject, let id = o["id"]?.asString, let instrument = o["instrument"]?.asString else { continue }
                presets[id] = SamplePresetInfo(
                    instrument: instrument,
                    kind: o["kind"]?.asString ?? "tonal",
                    gain: jnum(o, "gain", 1),
                    release: jnum(o, "release", 0.2)
                )
            }
        }

        let limits: JSONObject = root["limits"]?.asObject ?? JSONObject()
        let pattern: JSONObject = limits["patternLimits"]?.asObject ?? JSONObject()

        let styleIds: Set<String> = Set((root["styles"]?.asArray ?? []).compactMap { $0.asObject?["id"]?.asString })
        let sectionKinds: Set<String> = Set(root["sectionKinds"]?.asObject?.keys ?? [])
        let waveforms: Set<String> = Set(root["waveforms"]?.asObject?.keys ?? [])
        let barLengths: [Double] = (limits["barLengths"]?.asArray ?? []).compactMap { $0.asNumber }
        let maxBars: Int = limits["maxBars"]?.asNumber.map(Int.init) ?? 64
        let maxBeats: Double = jnum(limits, "maxBeats", 256)
        let maxNotes: Int = limits["maxProjectNotes"]?.asNumber.map(Int.init) ?? 12000
        let patternPatterns: Int = pattern["patterns"]?.asNumber.map(Int.init) ?? 64
        let patternNotes: Int = pattern["notes"]?.asNumber.map(Int.init) ?? 12000
        let patternPerPattern: Int = pattern["perPattern"]?.asNumber.map(Int.init) ?? 4000

        var styleList: [StyleInfo] = []
        if let styleArray = root["styles"]?.asArray {
            for sv in styleArray {
                guard let s = sv.asObject, let id = s["id"]?.asString else { continue }
                styleList.append(StyleInfo(
                    id: id,
                    name: s["name"]?.asString ?? id,
                    icon: s["icon"]?.asString ?? "",
                    desc: s["desc"]?.asString ?? "",
                    bpm: s["bpm"]?.asNumber ?? 86
                ))
            }
        }

        return TablesData(
            instruments: instruments,
            keys: keys,
            styleIds: styleIds,
            styles: styleList,
            sectionKinds: sectionKinds,
            waveforms: waveforms,
            soundDefaults: soundDefaults,
            soundDefinitions: soundDefinitions,
            controlDefaults: root["controlDefaults"]?.asObject ?? JSONObject(),
            barLengths: barLengths,
            maxBars: maxBars,
            maxBeats: maxBeats,
            maxProjectNotes: maxNotes,
            patternLimits: (patterns: patternPatterns, notes: patternNotes, perPattern: patternPerPattern),
            samplePresets: presets
        )
    }
}

// MARK: - 表驱动的校验原语

func validBars(_ bars: Double) -> Bool {
    jsIsInteger(bars) && Tables.shared.barLengths.contains(bars)
}

/// String(x || fallback).slice(0, n) 的 JS 语义(空串/缺省回落;数字/布尔按 JS 规则字符串化)。
func jsStringField(_ value: JSONValue?, fallback: String, limit: Int) -> String {
    let base: String
    switch value {
    case .none, .null: base = fallback
    case .string(let s): base = s.isEmpty ? fallback : s
    case .bool(let b): base = b ? "true" : "false"
    case .number(let d): base = jsNumber(d)
    default: base = fallback
    }
    return jsSlice16(base, limit)
}

/// JS String.prototype.slice(0, n) 按 UTF-16 码元截断。
func jsSlice16(_ s: String, _ n: Int) -> String {
    let units = Array(s.utf16)
    guard units.count > n else { return s }
    return String(decoding: units[0..<n], as: UTF16.self)
}
