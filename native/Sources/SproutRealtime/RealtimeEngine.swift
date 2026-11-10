// 实时播放引擎:AVAudioEngine + 逐音符缓冲调度。
// 发声路径与离线导出共用 renderEventVoice——播放听到的就是导出听到的。
// canImport 守卫:Linux CI 上此模块为空,保持 swift test 可跑。

#if canImport(AVFoundation)
import AVFoundation
import SproutKit
import SproutAudio

public final class RealtimeEngine {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var busMixers: [AVAudioMixerNode] = []
    private var tracks: [JSONObject] = []
    private var project: JSONObject?
    private var store: SampleStore?
    private var loopRange: (start: Double, end: Double) = (0, 16)
    private var spb: Double = 60.0 / 120

    private var playStartUptime: Double = 0
    private var startBeat: Double = 0
    private var pausedBeat: Double = 0
    private var loopTimer: Timer?
    public private(set) var playing = false
    public var onTransportChange: (() -> Void)?

    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 1)!
    private let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: renderSampleRate, channels: 2)!

    public init() {}

    // MARK: - 装载

    public func load(project: JSONObject, samplesRoot: URL?) throws {
        stop()
        let p = try validateProject(.object(project))
        self.project = p
        spb = 60 / jnum(p, "bpm", 120)
        tracks = (p["tracks"]?.asArray ?? []).compactMap(\.asObject)
        store = samplesRoot.map { SampleStore(root: $0) }
        if let range = p["loopRange"]?.asObject {
            loopRange = (jnum(range, "start"), jnum(range, "end"))
        } else {
            loopRange = (0, jnum(p, "bars", 4) * 4)
        }
        buildGraph()
        pausedBeat = loopRange.start
    }

    private func buildGraph() {
        for player in players { engine.detach(player) }
        for mixer in busMixers { engine.detach(mixer) }
        players.removeAll()
        busMixers.removeAll()
        for _ in tracks {
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: monoFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: stereoFormat)
            players.append(player)
            busMixers.append(mixer)
        }
        applyMix()
        engine.prepare()
    }

    /// 轨道混音(静音/独奏/音量/声像),播放中可实时调用。
    public func applyMix() {
        guard let project = project else { return }
        let master = jnum(project, "master", 0.75)
        engine.mainMixerNode.outputVolume = Float(master)
        let solo = tracks.contains { $0["solo"]?.asBool == true }
        for (i, t) in tracks.enumerated() {
            guard i < busMixers.count else { continue }
            let muted = t["muted"]?.asBool == true
            let tSolo = t["solo"]?.asBool == true
            busMixers[i].volume = (muted || (solo && !tSolo)) ? 0 : Float(jnum(t, "volume", 0.7))
            busMixers[i].pan = Float(jnum(t, "pan"))
        }
    }

    // MARK: - 播放

    public func play(from beat: Double? = nil) throws {
        guard let p = project else { return }
        let from = max(loopRange.start, min(beat ?? pausedBeat, loopRange.end - 0.001))
        if !engine.isRunning { try engine.start() }
        for player in players { player.stop() }

        let plan = try playbackPlan(p, range: projectRange(), from: from)
        var takeCounters: [String: Int] = [:]
        // 统一起点宿主时间:150ms 后开声,给调度留余量
        let leadSeconds = 0.15
        let hostStart = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: leadSeconds)
        for e in plan.events {
            guard e.trackIndex < players.count else { continue }
            let t = tracks[e.trackIndex]
            let key = "\(t["sampler"].flatMap { $0.asObject?["preset"]?.asString } ?? ""):\(Int(e.pitch))"
            let take = takeCounters[key] ?? 0
            takeCounters[key] = take + 1
            let voice = try renderEventVoice(event: e, track: t, bpm: jnum(p, "bpm", 120), rangeStart: plan.rangeStart, totalFrames: .max, store: store, take: take)
            guard !voice.samples.isEmpty else { continue }
            guard let buffer = pcmBuffer(voice.samples) else { continue }
            // 事件相对播放起点的秒数 → 宿主时间
            let offsetSeconds = Double(voice.startFrame) / renderSampleRate
            let at = AVAudioTime(hostTime: hostStart + AVAudioTime.hostTime(forSeconds: offsetSeconds))
            players[e.trackIndex].scheduleBuffer(buffer, at: at, options: [], completionHandler: nil)
        }
        let hostStartTime = AVAudioTime(hostTime: hostStart)
        for player in players { player.play(at: hostStartTime) }
        playing = true
        playStartUptime = ProcessInfo.processInfo.systemUptime + leadSeconds
        startBeat = from
        startLoopWatch(range: plan)
        onTransportChange?()
    }

    public func stop() {
        loopTimer?.invalidate()
        loopTimer = nil
        for player in players where player.isPlaying { player.stop() }
        if playing { pausedBeat = currentBeat }
        playing = false
        onTransportChange?()
    }

    public func toggle() {
        if playing { stop() } else { try? play() }
    }

    public var currentBeat: Double {
        guard playing else { return pausedBeat }
        return startBeat + (ProcessInfo.processInfo.systemUptime - playStartUptime) / spb
    }

    private func projectRange() -> JSONValue {
        guard let range = project?["loopRange"] else { return .null }
        return range
    }

    private func startLoopWatch(range: PlaybackPlan) {
        loopTimer?.invalidate()
        let end = range.rangeEnd
        let start = range.rangeStart
        loopTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if !self.playing { timer.invalidate(); return }
            if self.currentBeat >= end {
                self.pausedBeat = start
                try? self.play(from: start)
            }
        }
    }

    private func pcmBuffer(_ samples: [Double]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for (i, s) in samples.enumerated() { channel[i] = Float(max(-1, min(1, s))) }
        return buffer
    }
}
#endif
