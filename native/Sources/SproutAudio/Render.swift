// 离线渲染器:renderWAV 的原生移植(dist/audio.js renderWAV + createGraph +
// synthNote/synthConfiguredNote + sample-library play)。
// 混音在时域数组中逐样本完成:线性运算(轨道增益/声像/发送)与求和可交换,
// 母带压缩器与延迟回声按图结构顺序处理。全部确定性,同一输入逐字节同输出。

import Foundation
import SproutKit

public let renderSampleRate: Double = 44100

public struct RenderOptions {
    public var range: JSONValue?
    public var trackIds: [String]?
    public var samplesRoot: URL?
    public init(range: JSONValue? = nil, trackIds: [String]? = nil, samplesRoot: URL? = nil) {
        self.range = range
        self.trackIds = trackIds
        self.samplesRoot = samplesRoot
    }
}

// MARK: - 采样库(离线:按需加载 + SHA-256 校验)

public final class SampleStore {
    let root: URL
    var cache: [String: SampleBuffer] = [:]

    public init(root: URL) {
        self.root = root
    }

    func load(_ asset: SampleAsset) throws -> SampleBuffer {
        if let cached = cache[asset.id] { return cached }
        let url = root.appendingPathComponent(asset.file)
        guard let bytes = try? [UInt8](Data(contentsOf: url)) else {
            throw SproutError("采样加载失败：\(asset.id)。请重试或切回合成音源。")
        }
        guard bytes.count == asset.bytes, sha256Hex(bytes) == asset.sha256 else {
            throw SproutError("采样文件校验失败")
        }
        let buffer = try decodeSamplePCM(bytes)
        guard buffer.frames == asset.frames, buffer.sampleRate == asset.sampleRate,
              buffer.channels.count == asset.channels else {
            throw SproutError("采样参数不匹配")
        }
        cache[asset.id] = buffer
        return buffer
    }
}

// MARK: - 声部总线

struct TrackBus {
    let gain: Double
    let panL: Double, panR: Double
    let send: Double // 非鼓轨的延迟发送量(pad .45,其余 .23)
    let noise: [Double]
}

struct Bus {
    var dryL: [Double]
    var dryR: [Double]
    var sendL: [Double]
    var sendR: [Double]

    mutating func add(_ x: Double, at frame: Int, _ bus: TrackBus) {
        let l = x * bus.gain * bus.panL
        let r = x * bus.gain * bus.panR
        dryL[frame] += l
        dryR[frame] += r
        sendL[frame] += l * bus.send
        sendR[frame] += r * bus.send
    }
}

// MARK: - 采样发声

func renderSampleVoice(
    store: SampleStore,
    bus: TrackBus,
    instrument: String,
    settings: JSONValue,
    pitch: Int,
    when: Double,
    duration: Double,
    velocity: Int,
    into mix: inout Bus,
    take: Int
) throws {
    let config = try normalizeSampler(instrument, settings)
    let presetId = config["preset"]?.asString ?? ""
    let layers = try sampleLayers(presetId: presetId, pitch: pitch, velocity: velocity, take: take)
    for layer in layers {
        let buffer = try store.load(layer.asset)
        let plan = try sampleVoicePlan(
            instrument: instrument, settings: .object(config),
            pitch: pitch, duration: duration, velocity: velocity,
            bufferDuration: buffer.duration, assetId: layer.asset.id
        )
        let at = max(0, when)
        let end = at + plan.end
        let attack = min(plan.attack, (end - at) / 4)
        let releaseAt = min(max(at + attack, at + plan.releaseAt), end)
        let peak = plan.peak * layer.weight
        let startFrame = Int(at * renderSampleRate)
        let total = Int((end - at) * renderSampleRate)
        var filter = Biquad(lowpass: plan.cutoff, Q: 0.55, sampleRate: renderSampleRate)
        var pos = 0.0 // 缓冲内帧位置(浮点)
        let step = plan.rate * buffer.sampleRate / renderSampleRate
        let chan = buffer.channels[0]
        // loopStart/loopEnd 是秒(Web Audio loop 语义),换算为缓冲帧
        let loopStartFrame = plan.loopStart * buffer.sampleRate
        let loopEndFrame = plan.loopEnd * buffer.sampleRate
        for i in 0..<total {
            let frame = startFrame + i
            guard frame < mix.dryL.count else { break }
            var p = pos
            if plan.loop, p >= loopEndFrame {
                p -= (loopEndFrame - loopStartFrame)
                pos = p
            }
            let i0 = Int(p)
            let frac = p - Double(i0)
            let s0 = i0 < chan.count ? chan[i0] : 0
            let s1 = i0 + 1 < chan.count ? chan[i0 + 1] : s0
            let t = Double(i) / renderSampleRate
            var env: Double
            if t <= attack { env = peak * (attack > 0 ? t / attack : 1) }
            else if t <= releaseAt - at { env = peak }
            else { env = peak * max(0, 1 - (t - (releaseAt - at)) / max(0.0000001, end - releaseAt)) }
            let x = filter.process((s0 + (s1 - s0) * frac)) * env
            mix.add(x, at: frame, bus)
            pos += step
            if !plan.loop, pos >= Double(chan.count) { break }
        }
    }
}

// MARK: - 合成发声(默认参数路径,synthNote)

func renderSynthDefaultVoice(_ instrument: String, pitch: Double, when: Double, duration: Double, velocity: Double, bus: TrackBus, into mix: inout Bus) {
    let v = clamp(velocity / 127, 0, 1)
    let sr = renderSampleRate

    func envExp(_ v0: Double, _ target: Double, _ dt: Double, _ life: Double) -> Double {
        guard life > 0, v0 > 0 else { return 0 }
        return v0 * pow(target / v0, dt / life)
    }

    if instrument == "kick" {
        let start = Int(when * sr)
        let total = Int((0.4) * sr)
        for i in 0..<total {
            let frame = start + i
            guard frame < mix.dryL.count else { break }
            let dt = Double(i) / sr
            let freq = dt < 0.11 ? 145 * pow(43.0 / 145.0, dt / 0.11) : 43.0
            let x = sin(2 * Double.pi * freq * dt) * envExp(0.72 * v, 0.00001, dt, 0.37)
            mix.add(x, at: frame, bus)
        }
        return
    }
    if instrument == "snare" || instrument == "hat" {
        let isHat = instrument == "hat"
        let life = isHat ? 0.085 : 0.19
        let level = isHat ? 0.22 : 0.42
        var filter = isHat
            ? Biquad(highpass: 8000, Q: 0.7, sampleRate: sr)
            : Biquad(bandpass: 1800, Q: 0.65, sampleRate: sr)
        let start = Int(when * sr)
        let total = Int((life + 0.02) * sr)
        for i in 0..<total {
            let frame = start + i
            guard frame < mix.dryL.count else { break }
            let dt = Double(i) / sr
            let noise = bus.noise[(i + start) % bus.noise.count]
            let x = filter.process(noise) * envExp(level * v, 0.00001, dt, life)
            mix.add(x, at: frame, bus)
        }
        if instrument == "snare" {
            let startOsc = Int(when * sr)
            let totalOsc = Int(0.14 * sr)
            for i in 0..<totalOsc {
                let frame = startOsc + i
                guard frame < mix.dryL.count else { break }
                let dt = Double(i) / sr
                let x = oscSample(.triangle, dt * 175).truncatingRemainder(dividingBy: 1) * envExp(0.18 * v, 0.00001, dt, 0.12)
                mix.add(x, at: frame, bus)
            }
        }
        return
    }

    // 调性默认:attack .007 / hold d / ×.82 / exp release
    let d = max(0.04, duration)
    var attack = 0.007
    var release = 0.17
    var peak = 0.20 * v
    if instrument == "bass" { peak = 0.35 * v; release = 0.06 }
    if instrument == "pad" { attack = min(0.28, d / 3); release = 0.6; peak = 0.10 * v }
    if instrument == "lead" { peak = 0.16 * v; release = 0.15 }
    if instrument == "pluck" { peak = 0.17 * v; release = 0.24 }
    let cutoff = instrument == "bass" ? 800.0 : instrument == "pad" ? 1500.0 : 3200.0
    let hold = max(attack, d)
    let layers = synthLayers[instrument] ?? synthLayers["lead"]!
    let f = frequency(pitch)
    var filter = Biquad(lowpass: cutoff, Q: 0.55, sampleRate: sr)
    let start = Int(when * sr)
    let total = Int((d + release + 0.02) * sr)
    for i in 0..<total {
        let frame = start + i
        guard frame < mix.dryL.count else { break }
        let dt = Double(i) / sr
        var env: Double
        if dt < attack {
            env = 0.00001 + (peak - 0.00001) * dt / attack
        } else if dt < hold {
            env = peak
        } else {
            env = peak * 0.82 * pow(0.00001 / (peak * 0.82), (dt - hold) / release)
        }
        var x = 0.0
        for layer in layers {
            x += oscSample(OscWave(rawValue: layer.wave) ?? .triangle, (dt * f * layer.ratio).truncatingRemainder(dividingBy: 1)) * layer.volume
        }
        mix.add(filter.process(x) * env, at: frame, bus)
    }
}

// MARK: - 合成发声(配置参数路径,synthConfiguredNote)

func renderConfiguredVoice(_ instrument: String, pitch: Double, when: Double, duration: Double, velocity: Double, sound: JSONObject, bus: TrackBus, into mix: inout Bus) {
    let v = clamp(velocity / 127, 0, 1)
    let sr = renderSampleRate

    func envExp(_ v0: Double, _ target: Double, _ dt: Double, _ life: Double) -> Double {
        guard life > 0, v0 > 0 else { return 0 }
        return v0 * pow(target / v0, dt / life)
    }
    func hz(_ x: Double) -> Double { min(x, sr * 0.49) }

    if instrument == "kick" {
        let tone = jnum(sound, "tone", 43)
        let decay = jnum(sound, "decay", 0.37)
        let freq = hz(tone * 145 / 43)
        let finalFreq = hz(tone)
        let ramp = min(0.11, decay * 0.4)
        let start = Int(when * sr)
        let total = Int((decay + 0.02) * sr)
        var phase = 0.0
        for i in 0..<total {
            let frame = start + i
            guard frame < mix.dryL.count else { break }
            let dt = Double(i) / sr
            let f = dt < ramp ? freq * pow(finalFreq / freq, dt / ramp) : finalFreq
            phase += 2 * Double.pi * f / sr
            let x = sin(phase) * envExp(0.72 * v, 0.00001, dt, decay)
            mix.add(x, at: frame, bus)
        }
        return
    }
    if instrument == "snare" || instrument == "hat" {
        let isHat = instrument == "hat"
        let tone = sound["tone"]?.asNumber ?? (isHat ? 8000 : 1800)
        let decay = sound["decay"]?.asNumber ?? (isHat ? 0.085 : 0.19)
        let body = jnum(sound, "body", 0.3)
        if isHat || body < 1 {
            var filter = isHat
                ? Biquad(highpass: hz(tone), Q: 0.7, sampleRate: sr)
                : Biquad(bandpass: hz(tone), Q: 0.65, sampleRate: sr)
            let level = isHat ? 0.22 : 0.6 * (1 - body)
            let start = Int(when * sr)
            let total = Int((decay + 0.02) * sr)
            for i in 0..<total {
                let frame = start + i
                guard frame < mix.dryL.count else { break }
                let dt = Double(i) / sr
                let noise = bus.noise[(i + start) % bus.noise.count]
                let x = filter.process(noise) * envExp(level * v, 0.00001, dt, decay)
                mix.add(x, at: frame, bus)
            }
        }
        if instrument == "snare", body > 0 {
            let life = decay * 12 / 19
            let start = Int(when * sr)
            let total = Int((life + 0.02) * sr)
            for i in 0..<total {
                let frame = start + i
                guard frame < mix.dryL.count else { break }
                let dt = Double(i) / sr
                let x = oscSample(.triangle, (dt * 175).truncatingRemainder(dividingBy: 1)) * envExp(0.6 * body * v, 0.00001, dt, life)
                mix.add(x, at: frame, bus)
            }
        }
        return
    }

    // 调性:envelopePlan 逐点线性 + 峰值系数 + 滤波
    let plan = try! envelopePlan(duration: max(0.00005, duration), sound: sound)
    let peak = (synthPeak[instrument] ?? 0.2) * v
    let cutoff = jnum(sound, "cutoff", 3200)
    let resonance = jnum(sound, "resonance", 0.55)
    let waveform = sound["waveform"]?.asString ?? "native"
    let layers = synthLayers[instrument] ?? synthLayers["lead"]!
    let f = frequency(pitch)
    var filter = Biquad(lowpass: hz(cutoff), Q: resonance, sampleRate: sr)
    let start = Int(when * sr)
    let total = Int((plan.end + 0.02) * sr)
    for i in 0..<total {
        let frame = start + i
        guard frame < mix.dryL.count else { break }
        let dt = Double(i) / sr
        // 分段线性包络(envelopePlan.points)
        var env = 0.0
        var prevTime = 0.0, prevValue = 0.0
        var placed = false
        for point in plan.points.dropFirst() {
            if dt <= point.time {
                let span = point.time - prevTime
                env = prevValue + (point.value - prevValue) * (span > 0 ? (dt - prevTime) / span : 1)
                placed = true
                break
            }
            prevTime = point.time
            prevValue = point.value
        }
        if !placed { env = 0 }
        var x = 0.0
        for layer in layers {
            let wave = waveform == "native" ? (OscWave(rawValue: layer.wave) ?? .triangle) : (OscWave(rawValue: waveform) ?? .triangle)
            x += oscSample(wave, (dt * f * layer.ratio).truncatingRemainder(dividingBy: 1)) * layer.volume
        }
        mix.add(filter.process(x) * env * peak, at: frame, bus)
    }
}

// MARK: - renderWAV

public struct RenderStats {
    public let frames: Int
    public let seconds: Double
    public let peak: Double
    public let nonSilent: Bool
}

public func renderWAV(_ project: JSONObject, options: RenderOptions, store: SampleStore? = nil) throws -> (wav: [UInt8], stats: RenderStats) {
    let p = try validateProject(.object(project))
    let bpm = jnum(p, "bpm", 120)
    let plan = try playbackPlan(p, range: options.range ?? .null, trackIds: options.trackIds)
    let tail = audioTailSeconds(p)
    let seconds = plan.seconds + tail
    let frames = Int((seconds * renderSampleRate).rounded(.up))
    guard frames > 0, plan.events.count <= Tables.shared.maxProjectNotes else {
        throw SproutError("离线导出超过 12000 音符容量")
    }

    let tracks = (p["tracks"]?.asArray ?? []).compactMap(\.asObject)
    let solo = tracks.contains { $0["solo"]?.asBool == true }
    let noiseBuffer = LcgNoise.buffer(sampleRate: renderSampleRate)
    var buses: [Int: TrackBus] = [:]
    for (i, t) in tracks.enumerated() {
        let instrument = t["instrument"]?.asString ?? "lead"
        let kind = t["kind"]?.asString ?? "tonal"
        let muted = t["muted"]?.asBool == true
        let tSolo = t["solo"]?.asBool == true
        let gain = muted || (solo && !tSolo) ? 0 : (jnum(t, "volume", 0.7))
        let (panL, panR) = panGains(jnum(t, "pan", 0))
        let send = kind == "drum" ? 0 : (instrument == "pad" ? 0.45 : 0.23)
        buses[i] = TrackBus(gain: gain, panL: panL, panR: panR, send: send, noise: noiseBuffer)
    }

    var mix = Bus(
        dryL: [Double](repeating: 0, count: frames),
        dryR: [Double](repeating: 0, count: frames),
        sendL: [Double](repeating: 0, count: frames),
        sendR: [Double](repeating: 0, count: frames)
    )
    let sampleStore = store ?? (options.samplesRoot.map { SampleStore(root: $0) })
    var takeCounters: [String: Int] = [:]

    for e in plan.events {
        guard let bus = buses[e.trackIndex] else { continue }
        let t = tracks[e.trackIndex]
        let instrument = t["instrument"]?.asString ?? "lead"
        let when = (e.beat - plan.rangeStart) * 60 / bpm
        let duration = e.duration * 60 / bpm
        if let sampler = t["sampler"], let store = sampleStore {
            let key = "\((try? normalizeSampler(instrument, sampler))?["preset"]?.asString ?? ""):\(Int(e.pitch))"
            let take = takeCounters[key] ?? 0
            takeCounters[key] = (take + 1) &* 1
            try renderSampleVoice(
                store: store, bus: bus, instrument: instrument, settings: sampler,
                pitch: Int(e.pitch), when: when, duration: duration,
                velocity: Int(e.velocity), into: &mix, take: take
            )
        } else if let soundValue = t["sound"], let sound = soundValue.asObject {
            renderConfiguredVoice(instrument, pitch: e.pitch, when: when, duration: duration, velocity: e.velocity, sound: sound, bus: bus, into: &mix)
        } else {
            renderSynthDefaultVoice(instrument, pitch: e.pitch, when: when, duration: duration, velocity: e.velocity, bus: bus, into: &mix)
        }
    }

    // 延迟回声:createGraph 的 send→delay→damp→{feedback→delay, wet(.18)→master}
    let masterGain = jnum(p, "master", 0.75)
    let delaySec = min(0.36, 60 / bpm * 0.5)
    let delayFrames = max(1, Int(delaySec * renderSampleRate))
    var delayL = [Double](repeating: 0, count: delayFrames)
    var delayR = [Double](repeating: 0, count: delayFrames)
    var dampL = Biquad(lowpass: 2200, Q: 1, sampleRate: renderSampleRate)
    var dampR = Biquad(lowpass: 2200, Q: 1, sampleRate: renderSampleRate)
    var delayPos = 0
    var outL = [Double](repeating: 0, count: frames)
    var outR = [Double](repeating: 0, count: frames)
    var compressor = MasterCompressor(sampleRate: renderSampleRate)
    var peak = 0.0
    for i in 0..<frames {
        let readL = delayL[delayPos], readR = delayR[delayPos]
        let dL = dampL.process(readL), dR = dampR.process(readR)
        // wet → master;feedback → delay 输入
        let fbL = mix.sendL[i] + dL * 0.23
        let fbR = mix.sendR[i] + dR * 0.23
        delayL[delayPos] = fbL
        delayR[delayPos] = fbR
        delayPos = (delayPos + 1) % delayFrames
        var l = (mix.dryL[i] + dL * 0.18) * masterGain
        var r = (mix.dryR[i] + dR * 0.18) * masterGain
        l = compressor.process(l)
        r = compressor.process(r)
        peak = max(peak, abs(l), abs(r))
        outL[i] = l
        outR[i] = r
    }

    let wav = encodeWAV(left: outL, right: outR, sampleRate: renderSampleRate)
    return (wav, RenderStats(frames: frames, seconds: Double(frames) / renderSampleRate, peak: peak, nonSilent: peak > 0.01))
}
