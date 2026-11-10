// 发声参数纯函数:ADRS 包络计划(envelopePlan)与合成器层定义(synthConfiguredNote 的参数面)。
// 对应 dist/sound.js 的 envelopePlan 与 dist/audio.js 的振荡器层/峰值/滤波常量。
// 这些是算法常量(代码),不是数据表——与 audio.js 逐行对应。

import Foundation

public struct EnvelopePoint {
    public let time: Double
    public let value: Double
}

public struct EnvelopePlan {
    public let points: [EnvelopePoint]
    public let duration: Double
    public let end: Double       // duration + release
    public let offLevel: Double  // 松开瞬间的电平
}

public func envelopePlan(duration: Double, sound: JSONObject) throws -> EnvelopePlan {
    guard duration.isFinite, duration > 0 else { throw SproutError("音符时长须为正数") }
    let attack = jnum(sound, "attack", Double.nan)
    let decay = jnum(sound, "decay", Double.nan)
    let sustain = jnum(sound, "sustain", Double.nan)
    let release = jnum(sound, "release", Double.nan)
    guard [attack, decay, sustain, release].allSatisfy({ $0.isFinite }),
          attack > 0, decay > 0, release > 0, sustain >= 0, sustain <= 1 else {
        throw SproutError("包络参数不正确")
    }
    var points = [EnvelopePoint(time: 0, value: 0)]
    let attackEnd = min(duration, attack)
    points.append(EnvelopePoint(time: attackEnd, value: attackEnd / attack))
    if duration > attack {
        let decayEnd = min(duration, attack + decay)
        points.append(EnvelopePoint(time: decayEnd, value: 1 - (1 - sustain) * (decayEnd - attack) / decay))
        if duration > attack + decay {
            points.append(EnvelopePoint(time: duration, value: sustain))
        }
    }
    let offLevel = points[points.count - 1].value
    points.append(EnvelopePoint(time: duration + release, value: 0))
    return EnvelopePlan(points: points, duration: duration, end: duration + release, offLevel: offLevel)
}

// MARK: - 合成器层定义(audio.js synthConfiguredNote 的常量)

/// 调性乐器:[倍频, 波形, 层音量];'native' 波形按层用各自波形,否则统一覆盖。
public let synthLayers: [String: [(ratio: Double, wave: String, volume: Double)]] = [
    "keys": [(1, "sine", 1), (2, "sine", 0.25), (3, "sine", 0.08)],
    "pad": [(1, "triangle", 0.65), (1.004, "sine", 0.35)],
    "bass": [(1, "sine", 0.8), (1, "triangle", 0.2)],
    "pluck": [(1, "triangle", 0.8), (2, "sine", 0.2)],
    "lead": [(1, "triangle", 1)]
]

/// 乐器峰值系数(instrument==='bass'?.35:pad?.1:lead?.16:pluck?.17:.2)。
public let synthPeak: [String: Double] = ["bass": 0.35, "pad": 0.1, "lead": 0.16, "pluck": 0.17, "keys": 0.2]

public func frequency(_ pitch: Double) -> Double {
    440 * pow(2, (pitch - 69) / 12)
}

/// 一次合成发声的完整参数(渲染端按此建振荡器/滤波/包络)。
public struct SynthVoicePlan {
    public let layers: [(ratio: Double, wave: String, volume: Double, hz: Double)]
    public let envelope: EnvelopePlan
    public let peak: Double
    public let cutoff: Double
    public let resonance: Double
}

public func synthVoicePlan(instrument: String, pitch: Double, duration: Double, velocity: Double, sound: JSONValue) throws -> SynthVoicePlan {
    let cfg = try normalizeSound(instrument, sound)
    let base = synthLayers[instrument] ?? synthLayers["lead"]!
    let waveform = cfg["waveform"]?.asString ?? "native"
    let layers = base.map { layer in
        (layer.ratio, waveform == "native" ? layer.wave : waveform, layer.volume, frequency(pitch) * layer.ratio)
    }
    let env = try envelopePlan(duration: max(0.00005, duration), sound: cfg)
    let peak = (synthPeak[instrument] ?? 0.2) * clamp(velocity / 127, 0, 1)
    return SynthVoicePlan(
        layers: layers,
        envelope: env,
        peak: peak,
        cutoff: jnum(cfg, "cutoff", 3200),
        resonance: jnum(cfg, "resonance", 0.55)
    )
}

// MARK: - 音色快捷预设(sound.js soundPreset:soft / clear / short)

public let soundPresetIds = ["soft", "clear", "short"]

public func soundPreset(instrument: String, id: String) throws -> JSONObject {
    let defaults = try normalizeSound(instrument, .object(JSONObject()))
    guard soundPresetIds.contains(id), let definition = Tables.shared.soundDefinitions[instrument] else {
        throw SproutError("不存在这个音色预设")
    }
    var values = JSONObject()
    if definition.kind == "tonal" {
        let attack0 = jnum(defaults, "attack", 0.008)
        let release0 = jnum(defaults, "release", 0.17)
        let cutoff0 = jnum(defaults, "cutoff", 3200)
        if id == "soft" {
            values["attack"] = .number(max(0.05, attack0 * 1.5))
            values["decay"] = .number(0.4)
            values["sustain"] = .number(0.65)
            values["release"] = .number(min(1.8, release0 * 2 + 0.2))
            values["cutoff"] = .number(cutoff0 * 0.55)
            values["resonance"] = .number(0.5)
            values["waveform"] = .string("native")
        } else if id == "clear" {
            values["attack"] = .number(0.005)
            values["decay"] = .number(0.12)
            values["sustain"] = .number(0.75)
            values["release"] = .number(0.14)
            values["cutoff"] = .number(cutoff0 * 2.2)
            values["resonance"] = .number(0.65)
            values["waveform"] = .string("native")
        } else {
            values["attack"] = .number(0.003)
            values["decay"] = .number(0.08)
            values["sustain"] = .number(0.1)
            values["release"] = .number(0.055)
            values["cutoff"] = .number(cutoff0)
            values["resonance"] = .number(0.5)
            values["waveform"] = .string("native")
        }
    } else {
        let decay0 = jnum(defaults, "decay", 0.2)
        let tone0 = jnum(defaults, "tone", 1000)
        if id == "soft" {
            values["decay"] = .number(decay0 * 1.3)
            values["tone"] = .number(tone0 * 0.8)
        } else if id == "clear" {
            values["decay"] = .number(decay0 * 0.8)
            values["tone"] = .number(tone0 * 1.2)
        } else {
            values["decay"] = .number(decay0 * 0.4)
            values["tone"] = .number(tone0)
        }
        if instrument == "snare" {
            values["body"] = .number(id == "soft" ? 0.55 : id == "clear" ? 0.2 : 0.35)
        }
    }
    for field in definition.fields {
        if let raw = values[field.key]?.asNumber {
            values[field.key] = .number(round4(clamp(raw, field.min, field.max)))
        }
    }
    return try normalizeSound(instrument, .object(values))
}
