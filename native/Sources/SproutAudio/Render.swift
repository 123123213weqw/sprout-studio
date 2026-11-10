// 发声与混音。单音符先渲染成独立缓冲(VoiceRender,离线导出与实时播放共用同一条
// DSP 路径),离线渲染器再按轨道总线(增益/声像/延迟发送)叠加并过母带。

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

// MARK: - 采样库(按需加载 + SHA-256 校验)

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

// MARK: - 单音符缓冲

public struct VoiceRender {
    public let startFrame: Int
    public let samples: [Double]
}

@inline(__always)
func envExp(_ v0: Double, _ target: Double, _ dt: Double, _ life: Double) -> Double {
    guard life > 0, v0 > 0 else { return 0 }
    return v0 * pow(target / v0, dt / life)
}

/// 采样发声(sample-library play):层混合 + 梯形包络 + 变调 + 循环。
public func renderSampleVoiceBuffer(
    store: SampleStore,
    instrument: String,
    settings: JSONValue,
    pitch: Int,
    when: Double,
    duration: Double,
    velocity: Int,
    take: Int,
    totalFrames: Int
) throws -> VoiceRender {
    let config = try normalizeSampler(instrument, settings)
    let presetId = config["preset"]?.asString ?? ""
    let layers = try sampleLayers(presetId: presetId, pitch: pitch, velocity: velocity, take: take)
    var startFrame = Int.max
    var endFrame = 0
    var tails: [(offset: Int, samples: [Double])] = []
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
        let sFrame = Int(at * renderSampleRate)
        let total = Int((end - at) * renderSampleRate)
        var filter = Biquad(lowpass: plan.cutoff, Q: 0.55, sampleRate: renderSampleRate)
        var pos = 0.0
        let step = plan.rate * buffer.sampleRate / renderSampleRate
        let chan = buffer.channels[0]
        // loopStart/loopEnd 是秒(Web Audio loop 语义),换算为缓冲帧
        let loopStartFrame = plan.loopStart * buffer.sampleRate
        let loopEndFrame = plan.loopEnd * buffer.sampleRate
        var out = [Double](repeating: 0, count: max(0, total))
        for i in 0..<total {
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
            out[i] = filter.process(s0 + (s1 - s0) * frac) * env
            pos += step
            if !plan.loop, pos >= Double(chan.count) { break }
        }
        tails.append((sFrame, out))
        startFrame = min(startFrame, sFrame)
        endFrame = max(endFrame, sFrame + out.count)
    }
    guard startFrame != Int.max, endFrame > startFrame else { return VoiceRender(startFrame: 0, samples: []) }
    var mixdown = [Double](repeating: 0, count: endFrame - startFrame)
    for tail in tails {
        for (i, v) in tail.samples.enumerated() { mixdown[tail.offset - startFrame + i] += v }
    }
    if startFrame >= totalFrames { return VoiceRender(startFrame: startFrame, samples: []) }
    let clipped = min(mixdown.count, totalFrames - startFrame)
    return VoiceRender(startFrame: startFrame, samples: Array(mixdown[0..<clipped]))
}

/// 合成发声(默认参数,synthNote)。
public func renderSynthDefaultVoiceBuffer(_ instrument: String, pitch: Double, when: Double, duration: Double, velocity: Double, totalFrames: Int) -> VoiceRender {
    let v = clamp(velocity / 127, 0, 1)
    let sr = renderSampleRate
    let noiseBuffer = LcgNoise.buffer(sampleRate: sr)
    let cap = { (n: Int, start: Int) in max(0, min(n, totalFrames - start)) }

    if instrument == "kick" {
        let start = Int(when * sr)
        var out = [Double](repeating: 0, count: cap(Int(0.4 * sr), start))
        for i in 0..<out.count {
            let dt = Double(i) / sr
            let freq = dt < 0.11 ? 145 * pow(43.0 / 145.0, dt / 0.11) : 43.0
            out[i] = sin(2 * Double.pi * freq * dt) * envExp(0.72 * v, 0.00001, dt, 0.37)
        }
        return VoiceRender(startFrame: start, samples: out)
    }
    if instrument == "snare" || instrument == "hat" {
        let isHat = instrument == "hat"
        let life = isHat ? 0.085 : 0.19
        let level = isHat ? 0.22 : 0.42
        var filter = isHat
            ? Biquad(highpass: 8000, Q: 0.7, sampleRate: sr)
            : Biquad(bandpass: 1800, Q: 0.65, sampleRate: sr)
        let start = Int(when * sr)
        var out = [Double](repeating: 0, count: cap(Int((life + 0.02) * sr), start))
        for i in 0..<out.count {
            let dt = Double(i) / sr
            let noise = noiseBuffer[(i + start) % noiseBuffer.count]
            out[i] = filter.process(noise) * envExp(level * v, 0.00001, dt, life)
        }
        if instrument == "snare" {
            let tailCount = cap(Int(0.14 * sr), start)
            var merged = out
            for i in 0..<tailCount {
                let dt = Double(i) / sr
                let x = oscSample(.triangle, (dt * 175).truncatingRemainder(dividingBy: 1)) * envExp(0.18 * v, 0.00001, dt, 0.12)
                if i < merged.count { merged[i] += x } else { merged.append(x) }
            }
            return VoiceRender(startFrame: start, samples: merged)
        }
        return VoiceRender(startFrame: start, samples: out)
    }

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
    var out = [Double](repeating: 0, count: cap(Int((d + release + 0.02) * sr), start))
    for i in 0..<out.count {
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
        out[i] = filter.process(x) * env
    }
    return VoiceRender(startFrame: start, samples: out)
}

/// 合成发声(配置参数,synthConfiguredNote)。
public func renderConfiguredVoiceBuffer(_ instrument: String, pitch: Double, when: Double, duration: Double, velocity: Double, sound: JSONObject, totalFrames: Int) -> VoiceRender {
    let v = clamp(velocity / 127, 0, 1)
    let sr = renderSampleRate
    let noiseBuffer = LcgNoise.buffer(sampleRate: sr)
    let cap = { (n: Int, start: Int) in max(0, min(n, totalFrames - start)) }
    func hz(_ x: Double) -> Double { min(x, sr * 0.49) }

    if instrument == "kick" {
        let tone = jnum(sound, "tone", 43)
        let decay = jnum(sound, "decay", 0.37)
        let freq = hz(tone * 145 / 43)
        let finalFreq = hz(tone)
        let ramp = min(0.11, decay * 0.4)
        let start = Int(when * sr)
        var out = [Double](repeating: 0, count: cap(Int((decay + 0.02) * sr), start))
        var phase = 0.0
        for i in 0..<out.count {
            let dt = Double(i) / sr
            let f = dt < ramp ? freq * pow(finalFreq / freq, dt / ramp) : finalFreq
            phase += 2 * Double.pi * f / sr
            out[i] = sin(phase) * envExp(0.72 * v, 0.00001, dt, decay)
        }
        return VoiceRender(startFrame: start, samples: out)
    }
    if instrument == "snare" || instrument == "hat" {
        let isHat = instrument == "hat"
        let tone = jnum(sound, "tone", isHat ? 8000 : 1800)
        let decay = jnum(sound, "decay", isHat ? 0.085 : 0.19)
        let body = jnum(sound, "body", 0.3)
        let start = Int(when * sr)
        var out: [Double] = []
        if isHat || body < 1 {
            var filter = isHat
                ? Biquad(highpass: hz(tone), Q: 0.7, sampleRate: sr)
                : Biquad(bandpass: hz(tone), Q: 0.65, sampleRate: sr)
            let level = isHat ? 0.22 : 0.6 * (1 - body)
            out = [Double](repeating: 0, count: cap(Int((decay + 0.02) * sr), start))
            for i in 0..<out.count {
                let dt = Double(i) / sr
                let noise = noiseBuffer[(i + start) % noiseBuffer.count]
                out[i] = filter.process(noise) * envExp(level * v, 0.00001, dt, decay)
            }
        }
        if instrument == "snare", body > 0 {
            let life = decay * 12 / 19
            let tailCount = cap(Int((life + 0.02) * sr), start)
            for i in 0..<tailCount {
                let dt = Double(i) / sr
                let x = oscSample(.triangle, (dt * 175).truncatingRemainder(dividingBy: 1)) * envExp(0.6 * body * v, 0.00001, dt, life)
                if i < out.count { out[i] += x } else { out.append(x) }
            }
        }
        return VoiceRender(startFrame: start, samples: out)
    }

    let plan = try! envelopePlan(duration: max(0.00005, duration), sound: sound)
    let peak = (synthPeak[instrument] ?? 0.2) * v
    let cutoff = jnum(sound, "cutoff", 3200)
    let resonance = jnum(sound, "resonance", 0.55)
    let waveform = sound["waveform"]?.asString ?? "native"
    let layers = synthLayers[instrument] ?? synthLayers["lead"]!
    let f = frequency(pitch)
    var filter = Biquad(lowpass: hz(cutoff), Q: resonance, sampleRate: sr)
    let start = Int(when * sr)
    var out = [Double](repeating: 0, count: cap(Int((plan.end + 0.02) * sr), start))
    for i in 0..<out.count {
        let dt = Double(i) / sr
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
        out[i] = filter.process(x) * env * peak
    }
    return VoiceRender(startFrame: start, samples: out)
}

/// 事件 → 单音符缓冲(采样 / 配置合成 / 默认合成三选一)。
public func renderEventVoice(event: PlanEvent, track: JSONObject, bpm: Double, rangeStart: Double, totalFrames: Int, store: SampleStore?, take: Int) throws -> VoiceRender {
    let instrument = track["instrument"]?.asString ?? "lead"
    let when = (event.beat - rangeStart) * 60 / bpm
    let duration = event.duration * 60 / bpm
    if let sampler = track["sampler"], let store = store {
        return try renderSampleVoiceBuffer(
            store: store, instrument: instrument, settings: sampler,
            pitch: Int(event.pitch), when: when, duration: duration,
            velocity: Int(event.velocity), take: take, totalFrames: totalFrames
        )
    }
    if let soundValue = track["sound"], let sound = soundValue.asObject {
        return renderConfiguredVoiceBuffer(instrument, pitch: event.pitch, when: when, duration: duration, velocity: event.velocity, sound: sound, totalFrames: totalFrames)
    }
    return renderSynthDefaultVoiceBuffer(instrument, pitch: event.pitch, when: when, duration: duration, velocity: event.velocity, totalFrames: totalFrames)
}

// MARK: - 轨道总线与离线混音

struct TrackBus {
    let gain: Double
    let panL: Double, panR: Double
    let send: Double
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
    var buses: [Int: TrackBus] = [:]
    for (i, t) in tracks.enumerated() {
        let instrument = t["instrument"]?.asString ?? "lead"
        let kind = t["kind"]?.asString ?? "tonal"
        let muted = t["muted"]?.asBool == true
        let tSolo = t["solo"]?.asBool == true
        let gain = muted || (solo && !tSolo) ? 0 : jnum(t, "volume", 0.7)
        let (panL, panR) = panGains(jnum(t, "pan"))
        let send = kind == "drum" ? 0 : (instrument == "pad" ? 0.45 : 0.23)
        buses[i] = TrackBus(gain: gain, panL: panL, panR: panR, send: send)
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
        guard buses[e.trackIndex] != nil else { continue }
        let t = tracks[e.trackIndex]
        let key = "\(t["sampler"].flatMap { $0.asObject?["preset"]?.asString } ?? ""):\(Int(e.pitch))"
        let take = takeCounters[key] ?? 0
        takeCounters[key] = take + 1
        let voice = try renderEventVoice(event: e, track: t, bpm: bpm, rangeStart: plan.rangeStart, totalFrames: frames, store: sampleStore, take: take)
        let bus = buses[e.trackIndex]!
        for (i, x) in voice.samples.enumerated() {
            mix.add(x, at: voice.startFrame + i, bus)
        }
    }

    // 延迟回声 + 母带增益/压缩
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
        delayL[delayPos] = mix.sendL[i] + dL * 0.23
        delayR[delayPos] = mix.sendR[i] + dR * 0.23
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
