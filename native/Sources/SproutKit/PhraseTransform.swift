// 乐句变换:节奏倍速/倒序/移调/调内吸附/微偏移处理(phrase-transform.js 全量)。
// 整块语义:任何音符越界即整块拒绝;共享 Pattern 变动即解除关联。

import Foundation

public struct PhraseControls {
    public var ratio: Double = 1
    public var reverse = false
    public var transpose = 0
    public var scale = "keep"     // keep 或任一调性名
    public var timing = "follow"  // follow / keep / clear
    public var extend = false
    public init() {}
}

public func normalizePhraseControls(_ input: JSONObject) throws -> PhraseControls {
    let allowed = ["ratio", "reverse", "transpose", "scale", "timing", "extend"]
    for k in input.keys where !allowed.contains(k) { throw SproutError("乐句变换参数不正确") }
    var c = PhraseControls()
    if let v = input["ratio"]?.asNumber { c.ratio = v }
    if let v = input["reverse"]?.asBool { c.reverse = v }
    if let v = input["transpose"]?.asNumber { c.transpose = Int(v) }
    if let v = input["scale"]?.asString { c.scale = v }
    if let v = input["timing"]?.asString { c.timing = v }
    if let v = input["extend"]?.asBool { c.extend = v }
    let scaleOk = c.scale == "keep" || Tables.shared.keys[c.scale] != nil
    guard c.ratio == 0.5 || c.ratio == 1 || c.ratio == 2,
          c.transpose >= -24, c.transpose <= 24,
          scaleOk, c.timing == "follow" || c.timing == "keep" || c.timing == "clear" else {
        throw SproutError("请检查节奏倍数、倒序、半音或调内吸附参数")
    }
    return c
}

public func nearestScalePitch(_ pitch: Int, _ key: String) throws -> Int {
    guard pitch >= 24, pitch <= 108, let k = Tables.shared.keys[key] else {
        throw SproutError("音高或目标调性不正确")
    }
    var best = -1
    var distance = Double.infinity
    for p in 24...108 {
        let pc = ((p - Int(k.root)) % 12 + 12) % 12
        if k.scale.contains(where: { Int($0) == pc }) {
            let d = abs(Double(p - pitch))
            if d < distance { best = p; distance = d }
        }
    }
    return best
}

private func noteDiffers(_ a: JSONObject, _ b: JSONObject) -> Bool {
    jnum(a, "pitch") != jnum(b, "pitch")
        || jnum(a, "start") != jnum(b, "start")
        || jnum(a, "duration") != jnum(b, "duration")
        || jnum(a, "timingOffset") != jnum(b, "timingOffset")
        || a.has("timingOffset") != b.has("timingOffset")
}

/// 源音符集合 → 变换后音符(整块拒绝语义)。
public func transformPhraseNotes(_ notes: [JSONObject], start: Double, length: Double, kind: String, controls: JSONObject) throws -> (notes: [JSONObject], snapped: Int) {
    let c = try normalizePhraseControls(controls)
    let nextLength = round4(length * c.ratio)
    let end = round4(start + nextLength)
    guard start >= 0, length >= 0.25, length <= 256, kind == "tonal" || kind == "drum",
          nextLength >= 0.25, nextLength <= 256 else {
        throw SproutError("变换后音块长度须为 0.25–256 拍")
    }
    if kind == "drum" && (c.transpose != 0 || c.scale != "keep") {
        throw SproutError("鼓只变换节奏，不改变鼓音高或套用旋律音阶")
    }
    var snapped = 0
    var ids = Set<String>()
    var transformed: [JSONObject] = []
    for old in notes {
        let oldId = old["id"]?.asString ?? ""
        let pitch = jnum(old, "pitch")
        let noteStart = jnum(old, "start")
        let duration = jnum(old, "duration")
        let velocity = jnum(old, "velocity")
        let timingOffset = old.has("timingOffset") ? jnum(old, "timingOffset") : nil
        let idOk = jsSafeId(oldId) && !ids.contains(oldId)
        let pitchOk = jsIsInteger(pitch) && pitch >= 24 && pitch <= 108
        let velOk = jsIsInteger(velocity) && velocity >= 1 && velocity <= 127
        let spanOk = duration >= 0.03125
            && noteStart >= start - EPS && noteStart + duration <= start + length + EPS
        let timingOk = timingOffset == nil || (abs(timingOffset!) <= 0.04
            && noteStart + timingOffset! >= start - EPS
            && noteStart + timingOffset! + duration <= start + length + EPS)
        guard idOk, pitchOk, velOk, spanOk, timingOk, jsIsFinite(noteStart), jsIsFinite(duration) else {
            throw SproutError("源音符 / 标识 / 微偏移数据不正确")
        }
        ids.insert(oldId)

        var n = old
        let relative = round4(noteStart - start)
        n["duration"] = .number(round4(duration * c.ratio))
        let position = c.reverse ? (length - relative - duration) : relative
        n["start"] = .number(round4(start + position * c.ratio))

        let newPitch = Int(pitch) + c.transpose
        guard newPitch >= 24, newPitch <= 108 else {
            throw SproutError("移调越过 24–108 音高边界；不会自动折返八度或裁掉音符")
        }
        if c.scale == "keep" {
            n["pitch"] = .number(Double(newPitch))
        } else {
            let snappedPitch = try nearestScalePitch(newPitch, c.scale)
            n["pitch"] = .number(Double(snappedPitch))
            if snappedPitch != newPitch { snapped += 1 }
        }
        if c.timing == "clear" {
            n["timingOffset"] = nil
        } else if c.timing == "follow", let to = timingOffset {
            n["timingOffset"] = .number(round4(to * c.ratio * (c.reverse ? -1 : 1)))
        }
        // 变换后边界
        let nStart = jnum(n, "start"), nDur = jnum(n, "duration")
        let nTiming = n.has("timingOffset") ? jnum(n, "timingOffset") : 0
        let nOk = nDur >= 0.03125
            && nStart >= start - EPS && nStart + nDur <= end + EPS
            && abs(nTiming) <= 0.04
            && nStart + nTiming >= start - EPS
            && nStart + nTiming + nDur <= end + EPS
        guard nOk else {
            throw SproutError("变换后音符 / 微偏移过短或越界；整块拒绝，可选择清除微偏移或减少变换")
        }
        transformed.append(noteDiffers(old, n) ? n : old)
    }
    return (transformed, snapped)
}

/// 按演奏拍序的事件序列(performanceBeat),用于重叠检测。
struct PerformanceEvent {
    let noteId: String
    let pitch: Double
    let start: Double
    let end: Double
}

func performanceEvents(_ track: JSONObject, _ swing: Double) -> [PerformanceEvent] {
    let clips = jarr(track["clips"]).compactMap(jobj)
    var out: [PerformanceEvent] = []
    for n in audibleNotes(track) {
        let beat = performanceBeat(n, swing, clipAt(clips, jnum(n, "start")))
        out.append(PerformanceEvent(
            noteId: n["id"]?.asString ?? "",
            pitch: jnum(n, "pitch"),
            start: beat,
            end: beat + jnum(n, "duration", 0.125)
        ))
    }
    return stableSorted(out) { a, b in
        if a.pitch != b.pitch { return a.pitch < b.pitch }
        return a.start < b.start
    }
}

public func performanceOverlaps(_ track: JSONObject, _ swing: Double, _ ids: [String]) -> Int {
    let selected = Set(ids)
    var active: [PerformanceEvent] = []
    var count = 0
    var pitch: Double? = nil
    for event in performanceEvents(track, swing) {
        if pitch != event.pitch { active.removeAll(); pitch = event.pitch }
        active.removeAll { $0.end <= event.start + EPS }
        for earlier in active where selected.contains(earlier.noteId) || selected.contains(event.noteId) {
            count += 1
        }
        active.append(event)
    }
    return count
}

public struct PhraseTransformReport {
    public var changed = false
    public var targetNotes = 0
    public var changedNotes = 0
    public var snapped = 0
    public var detached = false
    public var clipChanged = false
    public var overlapsBefore = 0
    public var overlapsAfter = 0
}

public func planPhraseTransform(_ project: JSONObject, trackId: String, clipId: String, controls: JSONObject) throws -> (project: JSONObject, report: PhraseTransformReport) {
    let before = try validateProject(.object(project))
    let c = try normalizePhraseControls(controls)
    let beforeTracks = jarr(before["tracks"]).compactMap(jobj)
    guard let oldTrack = beforeTracks.first(where: { $0["id"]?.asString == trackId }),
          let oldClip = jarr(oldTrack["clips"]).compactMap(jobj).first(where: { $0["id"]?.asString == clipId }) else {
        throw SproutError("先选择仍存在的音块")
    }
    if oldTrack["kind"]?.asString == "drum" && (c.transpose != 0 || c.scale != "keep") {
        throw SproutError("鼓只变换节奏，不改变鼓音高或套用旋律音阶")
    }
    let source = notesInClip(oldTrack, oldClip)
    let oldLength = jnum(oldClip, "length", 4)
    let length = round4(oldLength * c.ratio)
    let end = round4(jnum(oldClip, "start") + length)
    guard length >= 0.25, length <= 256 else { throw SproutError("变换后音块长度须为 0.25–256 拍") }
    if end > jnum(before, "bars", 4) * 4 + EPS && !c.extend {
        throw SproutError("变换超出工程，请明确勾选空白延长")
    }
    var out = before
    let bars = end > jnum(before, "bars", 4) * 4 + EPS ? try expandedBars(end, current: jnum(before, "bars", 4)) : jnum(before, "bars", 4)
    // 撞块检查
    for x in jarr(oldTrack["clips"]).compactMap(jobj) {
        guard x["id"]?.asString != clipId else { continue }
        let xs = jnum(x, "start"), xl = jnum(x, "length", 4)
        if jnum(oldClip, "start") < xs + xl - EPS && end > xs + EPS {
            throw SproutError("变长后会碰到其他音块（空块也占位置）；整块没有改动")
        }
    }

    let selectedIds = Set(source.map { $0["id"]?.asString ?? "" })
    let result = try transformPhraseNotes(source, start: jnum(oldClip, "start"), length: oldLength, kind: oldTrack["kind"]?.asString ?? "tonal", controls: controls)
    let transformedById = Dictionary(uniqueKeysWithValues: result.notes.map { ($0["id"]?.asString ?? "", $0) })

    var report = PhraseTransformReport()
    report.targetNotes = source.count
    report.snapped = result.snapped
    var changedCount = 0
    for n in source where noteDiffers(n, transformedById[n["id"]?.asString ?? ""] ?? n) {
        changedCount += 1
    }
    let clipChanged = length != oldLength
    let changed = clipChanged || changedCount > 0
    report.changedNotes = changedCount
    report.clipChanged = clipChanged
    report.detached = oldClip.has("patternId") && changed

    report.overlapsBefore = performanceOverlaps(oldTrack, jnum(before, "swing"), Array(selectedIds))

    if changed {
        var tracksOut: [JSONValue] = []
        for tv in jarr(out["tracks"]) {
            guard var t = jobj(tv) else { tracksOut.append(tv); continue }
            if t["id"]?.asString == trackId {
                var clipsOut: [JSONValue] = []
                for cv in jarr(t["clips"]) {
                    guard var clip = jobj(cv) else { clipsOut.append(cv); continue }
                    if clip["id"]?.asString == clipId {
                        clip["length"] = .number(length)
                        if report.detached { clip["patternId"] = nil }
                        clipsOut.append(.object(clip))
                    } else {
                        clipsOut.append(cv)
                    }
                }
                t["clips"] = .array(clipsOut)
                t["notes"] = .array(jarr(t["notes"]).map { nv in
                    guard let n = jobj(nv) else { return nv }
                    if let replaced = transformedById[n["id"]?.asString ?? ""] { return .object(replaced) }
                    return nv
                })
            }
            tracksOut.append(.object(t))
        }
        out["tracks"] = .array(tracksOut)
        out["bars"] = .number(bars)
        let next = try validateProject(.object(out))
        if serializeProject(next).utf8.count > VaultLimits.projectBytes {
            throw SproutError("变换后工程超过 3 MB 保存上限，没有改动")
        }
        let nextTracks = jarr(next["tracks"]).compactMap(jobj)
        if let nextTrack = nextTracks.first(where: { $0["id"]?.asString == trackId }) {
            report.overlapsAfter = performanceOverlaps(nextTrack, jnum(next, "swing"), Array(selectedIds))
        }
        report.changed = true
        return (next, report)
    }
    report.overlapsAfter = report.overlapsBefore
    return (before, report)
}
