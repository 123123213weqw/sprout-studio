// normalize 家族:composition / range / sections / sound / sampler。
// 逐条对应 dist/composition.js、ranges.js、sections-core.js、sound.js、sampler-core.js,
// 错误文案是契约的一部分,不许改动。

import Foundation

let EPS = 0.00005

// MARK: - normalizeControls(composition.js)

public func normalizeControls(_ input: JSONValue, seed: Double) throws -> JSONObject {
    let defaults = Tables.shared.controlDefaults
    guard let obj = input.asObject else { throw SproutError("编曲参数须为对象") }
    for k in obj.keys where !defaults.has(k) { throw SproutError("包含未知的编曲参数") }

    var out = JSONObject()
    for (k, dv) in defaults.pairs {
        if k == "seed" {
            // {...CONTROL_DEFAULTS, seed, ...input}:输入 seed 优先于参数
            if let iv = obj[k], let n = iv.asNumber, jsIsFinite(n) {
                out[k] = .number(n)
            } else {
                out[k] = .number(jsIsFinite(seed) ? seed : jnum(defaults, "seed", 271828))
            }
        }
        else if let iv = obj[k] { out[k] = iv } else { out[k] = dv }
    }
    for key in ["density", "complexity", "energy", "humanize"] {
        guard let v = out[key]?.asNumber, jsIsFinite(v), v >= 0, v <= 100 else {
            throw SproutError("密度、复杂度、能量与人性化须为 0–100")
        }
        out[key] = .number((v).rounded(.toNearestOrAwayFromZero))
    }
    let progressionOK: Bool
    if case .string(let p)? = out["progression"] { progressionOK = ["warm", "lift", "home"].contains(p) }
    else { progressionOK = false }
    guard progressionOK, out["voiceLeading"]?.asBool != nil else {
        throw SproutError("和弦进行或声部连接参数不正确")
    }
    if let s = out["seed"]?.asNumber, !(jsIsInteger(s) && s >= 0 && s <= 4294967295) {
        throw SproutError("变奏种子须为 0–4294967295 整数")
    }
    return out
}

// MARK: - normalizeRange(ranges.js)

func normalizeRange(_ range: JSONValue, _ end: Double) throws -> JSONObject {
    guard jsIsFinite(end), end > 0 else { throw SproutError("工程播放长度不正确") }
    if case .null = range {
        return JSONObject([("start", .number(0)), ("end", .number(end))])
    }
    guard let obj = range.asObject,
          obj.keys.allSatisfy({ $0 == "start" || $0 == "end" }),
          let start = obj["start"]?.asNumber, let stop = obj["end"]?.asNumber,
          jsIsFinite(start), jsIsFinite(stop),
          start >= 0, stop <= end + EPS, stop - start >= 0.25 - EPS else {
        throw SproutError("练习范围须在工程内，且至少为四分之一拍")
    }
    var normalized = JSONObject()
    normalized["start"] = .number(round4(start))
    normalized["end"] = .number(round4(min(end, stop)))
    guard let ns = normalized["start"]?.asNumber, let ne = normalized["end"]?.asNumber,
          ne - ns >= 0.25 - EPS else {
        throw SproutError("舍入后的练习范围短于四分之一拍")
    }
    return normalized
}

// MARK: - normalizeSections(sections-core.js)

func normalizeSections(_ input: JSONValue, _ end: Double) throws -> [JSONValue] {
    guard let list = input.asArray, list.count <= Tables.shared.maxBars else {
        throw SproutError("歌曲段落最多 64 个")
    }
    var ids = Set<String>()
    var sections: [JSONObject] = []
    for sv in list {
        guard let s = sv.asObject,
              let id = s["id"]?.asString, jsSafeId(id), !ids.contains(id),
              let rawName = s["name"]?.asString, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rawName.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 40,
              let start = s["start"]?.asNumber, jsIsInteger(start), start >= 0,
              Int(start) % 4 == 0,
              let length = s["length"]?.asNumber, jsIsInteger(length), length >= 4,
              Int(length) % 4 == 0,
              start + length <= end else {
            throw SproutError("歌曲段落须有唯一标识、名称，且按完整小节放在工程内")
        }
        ids.insert(id)
        let kind: String
        switch s["kind"] {
        case .none: kind = "custom"
        case .string(let k): kind = k
        default: kind = "\u{0}" // 非字符串必不在 SECTION_KINDS,下面统一拒绝
        }
        guard Tables.shared.sectionKinds.contains(kind) else {
            throw SproutError("歌曲段落须有唯一标识、名称，且按完整小节放在工程内")
        }
        var out = JSONObject()
        out["id"] = .string(id)
        out["name"] = .string(rawName.trimmingCharacters(in: .whitespacesAndNewlines))
        out["kind"] = .string(kind)
        out["start"] = .number(start)
        out["length"] = .number(length)
        sections.append(out)
    }
    let sorted = stableSorted(sections) { a, b in
        (jnum(a, "start", 0)) < (jnum(b, "start", 0))
    }
    for i in stride(from: 1, to: sorted.count, by: 1) {
        let prev = sorted[i - 1], cur = sorted[i]
        if (jnum(cur, "start", 0)) < (jnum(prev, "start", 0)) + (jnum(prev, "length", 0)) {
            throw SproutError("歌曲段落不能重叠")
        }
    }
    return sorted.map { .object($0) }
}

// MARK: - normalizeSound(sound.js)

public func normalizeSound(_ instrument: String, _ input: JSONValue) throws -> JSONObject {
    guard let definition = Tables.shared.soundDefinitions[instrument],
          let defaults = Tables.shared.soundDefaults[instrument] else {
        throw SproutError("不支持的音源")
    }
    guard let obj = input.asObject else { throw SproutError("音色设置须为对象") }
    for k in obj.keys where !defaults.has(k) {
        throw SproutError("这个音源包含未知或不适用的音色参数")
    }
    var result = JSONObject()
    for (k, dv) in defaults.pairs {
        result[k] = obj[k] ?? dv
    }
    for field in definition.fields {
        let raw: Double? = result[field.key]?.asNumber
        let valid: Bool
        if let v = raw {
            valid = jsIsFinite(v) && v >= field.min && v <= field.max
        } else {
            valid = false
        }
        guard valid else {
            let message: String = field.label + "须为 " + jsNumber(field.min) + "–" + jsNumber(field.max) + " " + field.unit
            throw SproutError(message)
        }
        result[field.key] = .number(round4(raw!))
    }
    if definition.kind == "tonal" {
        guard let wf = result["waveform"]?.asString, Tables.shared.waveforms.contains(wf) else {
            throw SproutError("不支持的波形")
        }
    }
    return result
}

// MARK: - normalizeSampler(sampler-core.js)

public func normalizeSampler(_ instrument: String, _ input: JSONValue) throws -> JSONObject {
    guard Tables.shared.instruments[instrument] != nil,
          let obj = input.asObject,
          obj.keys.allSatisfy({ ["preset", "gain", "release", "cutoff"].contains($0) }) else {
        throw SproutError("采样设置不正确")
    }
    guard let presetId = obj["preset"]?.asString, let preset = Tables.shared.samplePresets[presetId] else {
        throw SproutError("不支持的采样音源")
    }
    guard preset.instrument == instrument else { throw SproutError("采样与当前音源不兼容") }

    var out = JSONObject()
    out["preset"] = .string(presetId)
    let gain = obj["gain"]?.asNumber ?? preset.gain
    let release = obj["release"]?.asNumber ?? preset.release
    let cutoff = jnum(obj, "cutoff", 18000)
    for (key, value, lo, hi) in [("gain", gain, 0.05, 1.5), ("release", release, 0.02, 2.0), ("cutoff", cutoff, 200.0, 18000.0)] {
        guard jsIsFinite(value), value >= lo, value <= hi else {
            throw SproutError("采样参数超出范围：" + key)
        }
        out[key] = .number(round4(value))
    }
    return out
}
