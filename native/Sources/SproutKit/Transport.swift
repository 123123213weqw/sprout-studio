// 播放计划:swing 拍点、事件窗口、节拍器。对应 dist/music.js 的
// swungBeat/performanceBeat 与 dist/transport.js 的 playbackPlan/timelineEvents。

public struct PlanEvent {
    public let trackIndex: Int
    public let noteId: String
    public let pitch: Double
    public let start: Double
    public let duration: Double
    public let velocity: Double
    public let timingOffset: Double?
    public let beat: Double
    public let originalBeat: Double
    public let resumed: Bool
    var isMetro: Bool { false }
}

public struct MetronomeEvent {
    public let beat: Double
    public let accent: Bool
}

public struct PlaybackPlan {
    public let rangeStart: Double
    public let rangeEnd: Double
    public let events: [PlanEvent]
    public let metronome: [MetronomeEvent]
    public let length: Double
    public let seconds: Double
}

public func swungBeat(_ start: Double, _ swing: Double) -> Double {
    let scaled = start * 4
    let tick = scaled.rounded(.toNearestOrAwayFromZero)
    if abs(scaled - tick) < 0.001, Int(tick) % 2 == 1 {
        return start + swing / 100 * 0.25
    }
    return start
}

public func performanceBeat(_ note: JSONObject, _ swing: Double, _ clip: JSONObject?) -> Double {
    var beat = swungBeat(note["start"]?.asNumber ?? 0, swing) + (note["timingOffset"]?.asNumber ?? 0)
    if let clip = clip {
        let cs = clip["start"]?.asNumber ?? 0
        let cl = clip["length"]?.asNumber ?? 0
        let nd = note["duration"]?.asNumber ?? 0
        beat = max(cs, min(beat, cs + cl - nd))
    }
    return beat
}

/// 音符所属音块(按起点,EPS 半开窗)。对应 clips.js 的 clipAt。
public func clipAt(_ clips: [JSONObject], _ beat: Double) -> JSONObject? {
    return clips.first { c in
        let cs = c["start"]?.asNumber ?? 0, cl = c["length"]?.asNumber ?? 0
        return beat >= cs - EPS && beat < cs + cl - EPS
    }
}

/// 未被静音音块拥有的音符(audibleNotes)。
public func audibleNotes(_ track: JSONObject) -> [JSONObject] {
    let clips = (track["clips"]?.asArray ?? []).compactMap(\.asObject)
    return (track["notes"]?.asArray ?? []).compactMap { nv in
        guard let n = nv.asObject else { return nil }
        let start = n["start"]?.asNumber ?? 0
        return clipAt(clips, start)?["muted"]?.asBool == true ? nil : n
    }
}

public func playbackPlan(_ project: JSONObject, range: JSONValue? = nil, trackIds: [String]? = nil, from: Double? = nil) throws -> PlaybackPlan {
    let bars = project["bars"]?.asNumber ?? 0
    let bpm = project["bpm"]?.asNumber ?? 120
    let swing = project["swing"]?.asNumber ?? 0
    let window = try normalizeRange(range ?? .null, bars * 4)
    let windowStart = window["start"]?.asNumber ?? 0
    let windowEnd = window["end"]?.asNumber ?? bars * 4

    var left = windowStart
    if let f = from {
        guard f.isFinite, f >= windowStart - EPS, f <= windowEnd + EPS else {
            throw SproutError("播放定位须在练习范围内")
        }
        left = f
    }
    let tracks = (project["tracks"]?.asArray ?? []).compactMap(\.asObject)
    if let ids = trackIds {
        guard !ids.isEmpty, ids.allSatisfy({ id in tracks.contains { $0["id"]?.asString == id } }) else {
            throw SproutError("预览轨道不存在")
        }
    }
    let idSet = trackIds.map(Set.init)

    var events: [PlanEvent] = []
    for (ti, t) in tracks.enumerated() {
        if let idSet, idSet.contains(t["id"]?.asString ?? "") == false { continue }
        let clips = (t["clips"]?.asArray ?? []).compactMap(\.asObject)
        for n in audibleNotes(t) {
            let originalBeat = performanceBeat(n, swing, clipAt(clips, n["start"]?.asNumber ?? 0))
            let noteDur = n["duration"]?.asNumber ?? 0
            let end = min(originalBeat + noteDur, windowEnd)
            let beat = max(originalBeat, left)
            if end - beat <= EPS { continue }
            events.append(PlanEvent(
                trackIndex: ti,
                noteId: n["id"]?.asString ?? "",
                pitch: n["pitch"]?.asNumber ?? 0,
                start: n["start"]?.asNumber ?? 0,
                duration: round4(end - beat),
                velocity: n["velocity"]?.asNumber ?? 0,
                timingOffset: n.has("timingOffset") ? n["timingOffset"]?.asNumber : nil,
                beat: round4(beat),
                originalBeat: originalBeat,
                resumed: originalBeat < left - EPS
            ))
        }
    }
    events = stableSorted(events) { a, b in
        if a.beat != b.beat { return a.beat < b.beat }
        return a.pitch < b.pitch
    }

    var metronome: [MetronomeEvent] = []
    var beat = (left - EPS).rounded(.up)
    while beat < windowEnd - EPS {
        metronome.append(MetronomeEvent(beat: beat, accent: Int(beat) % 4 == 0))
        beat += 1
    }

    return PlaybackPlan(
        rangeStart: windowStart,
        rangeEnd: windowEnd,
        events: events,
        metronome: metronome,
        length: windowEnd - windowStart,
        seconds: (windowEnd - windowStart) * 60 / bpm
    )
}

/// 事件与节拍器合并,音符先于同拍节拍器(timelineEvents)。
public func timelineEvents(_ plan: PlaybackPlan) -> [(beat: Double, isMetro: Bool, accent: Bool, event: PlanEvent?)] {
    var out: [(Double, Bool, Bool, PlanEvent?)] = plan.events.map { ($0.beat, false, false, $0) }
    out.append(contentsOf: plan.metronome.map { ($0.beat, true, $0.accent, nil) })
    return stableSorted(out) { a, b in
        if a.0 != b.0 { return a.0 < b.0 }
        // JS:Number(!!b.metro)-Number(!!a.metro) 为正时 note 在后 → 同拍时节拍器在前
        if a.1 != b.1 { return a.1 && !b.1 }
        return false
    }
}

extension PlaybackPlan {
    /// 对拍摘要行(与 tools/gen-m1-canonical.mjs 的 JS 摘要逐字段一致)。
    var digestLines: [String] {
        var lines = ["R|\(jsNumber(round4(rangeStart)))|\(jsNumber(round4(rangeEnd)))|\(jsNumber(round4(length)))|\(jsNumber(round4(seconds)))"]
        for e in timelineEvents(self) {
            if e.isMetro {
                lines.append("M|\(jsNumber(round4(e.beat)))|\(e.accent ? 1 : 0)")
            } else {
                let ev = e.event!
                let to = ev.timingOffset.map { jsNumber(round4($0)) } ?? "-"
                lines.append("E|\(jsNumber(round4(ev.beat)))|\(jsNumber(round4(ev.originalBeat)))|\(ev.resumed ? 1 : 0)|\(ev.trackIndex)|\(jsNumber(ev.pitch))|\(jsNumber(round4(ev.start)))|\(jsNumber(round4(ev.duration)))|\(jsNumber(ev.velocity))|\(to)")
            }
        }
        return lines
    }
}
