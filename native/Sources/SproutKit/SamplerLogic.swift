// 采样映射逻辑:shared/samples.json 加载 + pickSample / sampleLayers / sampleVoicePlan。
// 对应 dist/sampler-core.js 的纯函数部分;错误文案是契约。

import Foundation

public struct SampleAsset {
    public let id: String
    public let file: String
    public let bytes: Int
    public let sha256: String
    public let root: Int
    public let maxVelocity: Int
    public let frames: Int
    public let sampleRate: Double
    public let channels: Int
    public let peak: Double
    public let roundRobin: Int?
    public let velocityAnchor: Double?
    public let tuneCents: Double?
    public let loopStart: Double?
    public let loopEnd: Double?
}

public struct SamplePresetFull {
    let id: String
    let instrument: String
    let kind: String
    let gain: Double
    let release: Double
    let attack: Double?      // 缺省 .003(见 sampleVoicePlan)
    let balance: Double?
    let program: Int?
    let midiPitch: Int?
    let assets: [String]
}

public enum Samples {
    public static let shared: Data = load()

    public final class Data {
        public let presets: [String: SamplePresetFull]
        public let assets: [String: SampleAsset]
        /// preset → root → 力度层(每层内按 roundRobin 排序的 take 列表)
        public let zones: [String: [Int: [[SampleAsset]]]]

        init(presets: [String: SamplePresetFull], assets: [String: SampleAsset], zones: [String: [Int: [[SampleAsset]]]]) {
            self.presets = presets
            self.assets = assets
            self.zones = zones
        }
    }

    static func load() -> Data {
        guard let url = Bundle.module.url(forResource: "samples", withExtension: "json"),
              let text = try? String(contentsOfFile: url.path, encoding: .utf8),
              let value = try? parseJSON(text),
              let root = value.asObject else {
            fatalError("shared/samples.json 缺失或损坏:先运行 node tools/sync-shared.mjs")
        }

        var assets: [String: SampleAsset] = [:]
        for av in (root["assets"]?.asArray ?? []) {
            guard let a = av.asObject, let id = a["id"]?.asString else { continue }
            assets[id] = SampleAsset(
                id: id,
                file: a["file"]?.asString ?? "",
                bytes: a["bytes"]?.asNumber.map(Int.init) ?? 0,
                sha256: a["sha256"]?.asString ?? "",
                root: a["root"]?.asNumber.map(Int.init) ?? 60,
                maxVelocity: a["maxVelocity"]?.asNumber.map(Int.init) ?? 127,
                frames: a["frames"]?.asNumber.map(Int.init) ?? 0,
                sampleRate: jnum(a, "sampleRate", 44100),
                channels: a["channels"]?.asNumber.map(Int.init) ?? 1,
                peak: jnum(a, "peak", 1),
                roundRobin: a["roundRobin"]?.asNumber.map(Int.init),
                velocityAnchor: a["velocityAnchor"]?.asNumber,
                tuneCents: a["tuneCents"]?.asNumber,
                loopStart: a["loopStart"]?.asNumber,
                loopEnd: a["loopEnd"]?.asNumber
            )
        }

        var presets: [String: SamplePresetFull] = [:]
        if let presetObj = root["presets"]?.asObject {
            for (id, pv) in presetObj.pairs {
                guard let p = pv.asObject else { continue }
                presets[id] = SamplePresetFull(
                    id: id,
                    instrument: p["instrument"]?.asString ?? "",
                    kind: p["kind"]?.asString ?? "tonal",
                    gain: jnum(p, "gain", 1),
                    release: jnum(p, "release", 0.2),
                    attack: p["attack"]?.asNumber,
                    balance: p["balance"]?.asNumber,
                    program: p["program"]?.asNumber.map(Int.init),
                    midiPitch: p["midiPitch"]?.asNumber.map(Int.init),
                    assets: (p["assets"]?.asArray ?? []).compactMap(\.asString)
                )
            }
        }

        // presetZones:root 分组,组内先按 maxVelocity 分层,层内按 roundRobin 排
        var zones: [String: [Int: [[SampleAsset]]]] = [:]
        for (id, preset) in presets {
            var byRoot: [Int: [SampleAsset]] = [:]
            for assetId in preset.assets {
                guard let a = assets[assetId] else { continue }
                byRoot[a.root, default: []].append(a)
            }
            var rooted: [Int: [[SampleAsset]]] = [:]
            for (root, group) in byRoot {
                var layers: [Int: [SampleAsset]] = [:]
                for a in group { layers[a.maxVelocity, default: []].append(a) }
                rooted[root] = layers.keys.sorted().map { v in
                    stableSorted(layers[v]!) { ($0.roundRobin ?? 0) < ($1.roundRobin ?? 0) }
                }
            }
            zones[id] = rooted
        }
        return Data(presets: presets, assets: assets, zones: zones)
    }

    static func samplePreset(_ id: String) throws -> SamplePresetFull {
        guard let preset = Samples.shared.presets[id] else { throw SproutError("不支持的采样音源") }
        return preset
    }

    static func sampleAsset(_ id: String) throws -> SampleAsset {
        guard let asset = Samples.shared.assets[id] else { throw SproutError("采样文件不存在") }
        return asset
    }
}

// MARK: - 选择逻辑(sampler-core.js)

private func takeIndex(_ take: Int) throws {
    guard take >= 0, take <= 0xffffffff else { throw SproutError("Invalid recorded take index") }
}

/// 选根音最近的力度层内第 take 个录音。
public func pickSample(presetId: String, pitch: Int, velocity: Int, take: Int = 0) throws -> SampleAsset {
    _ = try Samples.samplePreset(presetId)
    try takeIndex(take)
    guard pitch >= 24, pitch <= 108, velocity >= 1, velocity <= 127 else {
        throw SproutError("采样音符参数不正确")
    }
    guard let zones = Samples.shared.zones[presetId], !zones.isEmpty else { throw SproutError("采样文件不存在") }
    // 根音按 |root - pitch| 升序,再按 root 升序(与 JS 的复合比较一致)
    let roots = zones.keys.sorted { abs($0 - pitch) < abs($1 - pitch) || (abs($0 - pitch) == abs($1 - pitch) && $0 < $1) }
    guard let layers = zones[roots[0]], !layers.isEmpty else { throw SproutError("采样文件不存在") }
    let chosen = layers.first { velocity <= $0[0].maxVelocity } ?? layers[layers.count - 1]
    return chosen[take % chosen.count]
}

/// 力度层混合:velocityAnchor 存在时按录制动态中心线性混合,否则走旧版两层混合。
public func sampleLayers(presetId: String, pitch: Int, velocity: Int, take: Int = 0) throws -> [(asset: SampleAsset, weight: Double)] {
    let chosen = try pickSample(presetId: presetId, pitch: pitch, velocity: velocity, take: take)
    guard let layers = Samples.shared.zones[presetId]?[chosen.root], !layers.isEmpty else {
        throw SproutError("采样文件不存在")
    }
    func at(_ i: Int) -> SampleAsset { layers[i][take % layers[i].count] }
    if layers.count == 1 { return [(at(0), 1)] }
    let anchors = layers.map { $0[0].velocityAnchor }
    if anchors.allSatisfy({ $0 != nil }) {
        let values = anchors.map { $0! }
        if Double(velocity) <= values[0] { return [(at(0), 1)] }
        if Double(velocity) >= values[values.count - 1] { return [(at(layers.count - 1), 1)] }
        var hi = 0
        for (i, a) in values.enumerated() where Double(velocity) <= a { hi = i; break }
        let lo = hi - 1
        let mix = (Double(velocity) - values[lo]) / (values[hi] - values[lo])
        var out: [(SampleAsset, Double)] = [(at(lo), 1 - mix), (at(hi), mix)]
        out.removeAll { $0.1 <= 0 }
        return out
    }
    let mix = (Double(velocity) - 1) / 126
    var out: [(SampleAsset, Double)] = [(at(0), 1 - mix), (at(layers.count - 1), mix)]
    out.removeAll { $0.1 <= 0 }
    return out
}

/// 一次采样发声的全部参数(速率/循环/包络关键点/峰值)。
public struct SampleVoicePlan {
    public let asset: SampleAsset
    public let rate: Double
    public let end: Double
    public let releaseAt: Double
    public let attack: Double
    public let peak: Double
    public let cutoff: Double
    public let loop: Bool
    public let loopStart: Double
    public let loopEnd: Double
}

public func sampleVoicePlan(instrument: String, settings: JSONValue, pitch: Int, duration: Double, velocity: Int, bufferDuration: Double, assetId: String? = nil) throws -> SampleVoicePlan {
    let config = try normalizeSampler(instrument, settings)
    let configPresetId = config["preset"]?.asString ?? ""
    let configGain = jnum(config, "gain", 1)
    let configRelease = jnum(config, "release", 0.2)
    let configCutoff = jnum(config, "cutoff", 18000)
    let preset = try Samples.samplePreset(configPresetId)
    let chosen = try pickSample(presetId: configPresetId, pitch: pitch, velocity: velocity)
    let asset: SampleAsset
    if let assetId = assetId {
        asset = try Samples.sampleAsset(assetId)
        guard preset.assets.contains(asset.id), asset.root == chosen.root else {
            throw SproutError("采样层不兼容")
        }
    } else {
        asset = chosen
    }
    guard duration.isFinite, duration > 0, bufferDuration.isFinite, bufferDuration > 0 else {
        throw SproutError("采样播放长度不正确")
    }
    let hasLoop = preset.kind == "tonal"
        && asset.loopStart.map { $0.isFinite } == true
        && asset.loopEnd.map { $0.isFinite } == true
        && asset.loopStart! >= 0 && asset.loopEnd! > asset.loopStart! && asset.loopEnd! <= bufferDuration
    let rate = preset.kind == "tonal"
        ? pow(2, (Double(pitch - asset.root) + (asset.tuneCents ?? 0) / 100) / 12)
        : 1
    let natural = bufferDuration / rate
    let end = hasLoop ? duration + configRelease
        : min(natural, preset.kind == "tonal" ? duration + configRelease : configRelease)
    let releaseAt = preset.kind == "tonal"
        ? min(duration, max(0, end - 0.01))
        : max(0, end - min(0.04, end / 4))
    let zonePeak = Samples.shared.zones[configPresetId]?[asset.root]?.flatMap { $0 }.map(\.peak).max() ?? 1
    let balance = preset.balance.map { min(4, $0 / zonePeak) } ?? 1
    return SampleVoicePlan(
        asset: asset,
        rate: rate,
        end: end,
        releaseAt: releaseAt,
        attack: min(preset.attack ?? 0.003, end / 4),
        peak: configGain * (Double(velocity) / 127) * (preset.kind == "tonal" ? 0.6 : 0.8) * balance,
        cutoff: configCutoff,
        loop: hasLoop,
        loopStart: hasLoop ? asset.loopStart! : 0,
        loopEnd: hasLoop ? asset.loopEnd! : 0
    )
}

extension SampleVoicePlan {
    /// 签名摘要用(对拍):固定字段四舍五入后拼接。
    var digestLine: String {
        "\(asset.id)|rate:\(String(format: "%.6f", rate))|end:\(String(format: "%.4f", end))|rel:\(String(format: "%.4f", releaseAt))|atk:\(String(format: "%.4f", attack))|peak:\(String(format: "%.6f", peak))|loop:\(loop ? 1 : 0)"
    }
}

// MARK: - 音高集合所需的资产(sampleAssetsForPitches)

public func sampleAssetsForPitches(presetId: String, pitches: [Int]?) throws -> [String] {
    let preset = try Samples.samplePreset(presetId)
    guard let pitches = pitches else { return preset.assets }
    guard pitches.count <= 12000 else { throw SproutError("Invalid sample pitch selection") }
    var roots = Set<Int>()
    for p in pitches { roots.insert(try pickSample(presetId: presetId, pitch: p, velocity: 64).root) }
    return preset.assets.filter { Samples.shared.assets[$0].map { roots.contains($0.root) } == true }
}

/// audioTailSeconds(sound.js):离线渲染的尾部时长。
public func audioTailSeconds(_ project: JSONObject) -> Double {
    var tail = 1.5
    for tv in (project["tracks"]?.asArray ?? []) {
        guard let t = tv.asObject else { continue }
        let instrument = t["instrument"]?.asString ?? ""
        let kind = t["kind"]?.asString ?? "tonal"
        if let sampler = t["sampler"] {
            let s = (try? normalizeSampler(instrument, sampler)) ?? JSONObject()
            tail = max(tail, (jnum(s, "release", 0)) + 1.02)
        } else if let sound = t["sound"] {
            let s = (try? normalizeSound(instrument, sound)) ?? JSONObject()
            let extra = kind == "drum" ? (jnum(s, "decay", 0)) + 0.02 : (jnum(s, "release", 0)) + 0.02
            tail = max(tail, extra + 1)
        }
    }
    return round4(tail)
}
