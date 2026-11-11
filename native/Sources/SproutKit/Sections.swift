// 歌曲段落:CRUD/骨架模板 + 过门填充(section-transition.js 全量)。
// 错误文案与报告结构一致;输出经 validateProject(ensureClips strict)。

import Foundation

public func sectionAt(_ project: JSONObject, _ id: String) throws -> JSONObject {
    for sv in jarr(project["sections"]) {
        if let s = jobj(sv), s["id"]?.asString == id { return s }
    }
    throw SproutError("请先选择一个歌曲段落")
}

public func updateSection(_ project: JSONObject, id: String? = nil, name: String, kind: String = "custom", start: Double, length: Double) throws -> (project: JSONObject, sectionId: String) {
    var out = project
    if let id = id, !jarr(out["sections"]).contains(where: { jobj($0)?["id"]?.asString == id }) {
        throw SproutError("段落已不存在")
    }
    var section = JSONObject()
    let sectionId = id ?? jsUid()
    section["id"] = .string(sectionId)
    section["name"] = .string(name)
    section["kind"] = .string(kind)
    section["start"] = .number(start)
    section["length"] = .number(length)
    let kept = jarr(out["sections"]).filter { jobj($0)?["id"]?.asString != id }
    out["sections"] = .array(try normalizeSections(.array(kept + [.object(section)]), jnum(out, "bars", 4) * 4))
    return (try validateProject(.object(out)), sectionId)
}

public func deleteSection(_ project: JSONObject, id: String) throws -> JSONObject {
    var out = project
    out["sections"] = .array(jarr(out["sections"]).filter { jobj($0)?["id"]?.asString != id })
    if jarr(out["sections"]).isEmpty { out["sections"] = nil }
    return try validateProject(.object(out))
}

public func sectionTemplate(_ project: JSONObject, template: String = "verse-chorus") throws -> JSONObject {
    var out = project
    let end = jnum(out, "bars", 4) * 4
    let kinds: [String]?
    if template == "verse-chorus" { kinds = ["verse", "chorus"] }
    else if template == "four-parts" { kinds = ["intro", "verse", "chorus", "outro"] }
    else { kinds = nil }
    guard let kinds = kinds else { throw SproutError("歌曲骨架不正确") }
    let length = end / Double(kinds.count)
    var sections: [JSONValue] = []
    for (i, kind) in kinds.enumerated() {
        var s = JSONObject()
        s["id"] = .string(jsUid())
        s["name"] = .string(sectionKindName(kind))
        s["kind"] = .string(kind)
        s["start"] = .number(Double(i) * length)
        s["length"] = .number(length)
        sections.append(.object(s))
    }
    out["sections"] = .array(sections)
    return try validateProject(.object(out))
}

func sectionKindName(_ kind: String) -> String {
    let names = ["intro": "前奏", "verse": "主歌", "chorus": "副歌", "bridge": "过渡", "outro": "尾奏", "custom": "自定义"]
    return names[kind] ?? "自定义"
}

// MARK: - 过门(section-transition.js)

public let fillStyles = ["gentle": "轻轻带过去", "rise": "逐渐加密", "break": "留半拍呼吸"]

public struct FillControls {
    public var style: String = "gentle"
    public var bars: Int = 1
    public var energy: Int = 70
    public var seed: Int = 1
    public var fillGaps: Bool = false
    public init() {}
}

public func normalizeFillControls(_ controls: JSONObject) throws -> FillControls {
    let allowed = ["style", "bars", "energy", "seed", "fillGaps"]
    for k in controls.keys where !allowed.contains(k) {
        throw SproutError("过门参数不正确")
    }
    var c = FillControls()
    if let v = controls["style"]?.asString { c.style = v }
    if let v = controls["bars"]?.asNumber { c.bars = Int(v) }
    if let v = controls["energy"]?.asNumber { c.energy = Int(v) }
    if let v = controls["seed"]?.asNumber { c.seed = Int(v) }
    if let v = controls["fillGaps"]?.asBool { c.fillGaps = v }
    guard fillStyles[c.style] != nil, c.bars == 1 || c.bars == 2,
          c.energy >= 30, c.energy <= 100, c.seed >= 1, c.seed <= 2147483647 else {
        throw SproutError("过门须为 1 / 2 小节、能量 30–100、种子 1–2147483647")
    }
    return c
}

public func fillPositions(instrument: String, style: String, bars: Int) throws -> [Double] {
    guard ["kick", "snare", "hat"].contains(instrument), fillStyles[style] != nil, bars == 1 || bars == 2 else {
        throw SproutError("过门鼓型不正确")
    }
    var result: [Double] = []
    for bar in 0..<bars {
        let last = bar == bars - 1
        var beats: [Double]
        if !last {
            beats = instrument == "kick" ? [0, 2] : instrument == "snare" ? [1, 3] : Array(0..<8).map { Double($0) / 2 }
        } else if style == "gentle" {
            beats = instrument == "kick" ? [0, 2] : instrument == "snare" ? [1, 3, 3.5] : Array(0..<8).map { Double($0) / 2 }
        } else if style == "rise" {
            beats = instrument == "kick" ? [0, 2, 2.5, 3]
                : instrument == "snare" ? [1, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75]
                : [0, 0.5, 1, 1.5, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75]
        } else {
            beats = instrument == "kick" ? [0] : instrument == "snare" ? [1, 2, 2.5, 3] : [0, 0.5, 1, 1.5, 2, 2.5, 3]
        }
        for beat in beats { result.append(Double(bar * 4) + beat) }
    }
    return result
}

public struct FillReport {
    public let start: Double
    public let end: Double
    public var addedNotes = 0
    public var removedNotes = 0
    public var trimmedNotes = 0
    public var newClips = 0
    public var detached = 0
}

public func planSectionFill(_ project: JSONObject, sectionId: String, trackIds: [String], controls: JSONObject) throws -> (project: JSONObject, report: FillReport) {
    let before = try validateProject(.object(project))
    let section = try sectionAt(before, sectionId)
    let c = try normalizeFillControls(controls)
    let end = jnum(section, "start") + jnum(section, "length", 4)
    let start = end - Double(c.bars * 4)
    if start < jnum(section, "start") { throw SproutError("段落不够长，不能放入这次过门") }

    let beforeTracks = jarr(before["tracks"]).compactMap(jobj)
    guard !trackIds.isEmpty, Set(trackIds).count == trackIds.count,
          trackIds.allSatisfy({ id in beforeTracks.contains { t in t["id"]?.asString == id && t["kind"]?.asString == "drum" } }) else {
        throw SproutError("请选择至少一条现有鼓轨，不得重复或选择旋律轨")
    }

    var out = before
    var report = FillReport(start: start, end: end)
    var tracksOut: [JSONValue] = []
    for tv in jarr(out["tracks"]) {
        guard var track = jobj(tv) else { tracksOut.append(tv); continue }
        guard trackIds.contains(track["id"]?.asString ?? "") else { tracksOut.append(tv); continue }
        guard let old = beforeTracks.first(where: { $0["id"]?.asString == track["id"]?.asString }) else { continue }
        let trackId = track["id"]?.asString ?? ""
        let instrument = track["instrument"]?.asString ?? "kick"
        let pitch = Double(Tables.shared.instruments[instrument]?.pitch ?? 36)

        // 1) 裁掉过门窗内的旧音符(边缘长音切成两段保留)
        var kept: [JSONValue] = []
        for nv in jarr(track["notes"]) {
            guard let note = jobj(nv) else { kept.append(nv); continue }
            let noteStart = jnum(note, "start")
            let stop = round4(noteStart + jnum(note, "duration", 0.125))
            if stop <= start + EPS || noteStart >= end - EPS { kept.append(nv); continue }
            var pieces: [(Double, Double)] = []
            if noteStart < start - EPS { pieces.append((noteStart, start)) }
            if stop > end + EPS { pieces.append((end, stop)) }
            if pieces.isEmpty { report.removedNotes += 1; continue }
            report.trimmedNotes += 1
            for (i, piece) in pieces.enumerated() {
                if piece.1 - piece.0 < 0.03125 - EPS { throw SproutError("边界长音会留下过短片段，请先调整音符") }
                var n = note
                if i > 0 { n["id"] = .string(jsUid()) }
                n["start"] = .number(round4(piece.0))
                n["duration"] = .number(round4(piece.1 - piece.0))
                if n.has("timingOffset") {
                    let offset = round4(max(piece.0 - jnum(n, "start"), min(jnum(n, "timingOffset"), piece.1 - jnum(n, "start") - jnum(n, "duration"))))
                    n["timingOffset"] = .number(offset)
                }
                kept.append(.object(n))
            }
        }
        track["notes"] = .array(kept)

        // 2) 音块空隙检查(可勾选新建)
        let positions = try fillPositions(instrument: instrument, style: c.style, bars: c.bars).map { round4(start + $0) }
        var gaps: [(Double, Double)] = []
        var cursor = start
        let clipsBefore = jarr(track["clips"]).compactMap(jobj)
        for clip in clipsBefore {
            let cs = jnum(clip, "start"), cl = jnum(clip, "length", 4)
            if cs + cl <= start + EPS || cs >= end - EPS { continue }
            if cs > cursor + EPS { gaps.append((cursor, min(end, cs))) }
            cursor = max(cursor, min(end, cs + cl))
        }
        if cursor < end - EPS { gaps.append((cursor, end)) }
        for gap in gaps where positions.contains(where: { $0 >= gap.0 - EPS && $0 < gap.1 - EPS }) {
            if !c.fillGaps { throw SproutError("“\(track["name"]?.asString ?? "")”过门位置有空白。可明确勾选“在空白处新建音块”") }
            if gap.1 - gap.0 < 0.25 - EPS { throw SproutError("过门空隙不足 1/4 拍，不能新建音块") }
            var newClip = JSONObject()
            newClip["id"] = .string(jsUid())
            newClip["name"] = .string("过门 · " + (fillStyles[c.style] ?? ""))
            newClip["start"] = .number(round4(gap.0))
            newClip["length"] = .number(round4(gap.1 - gap.0))
            newClip["muted"] = .bool(false)
            var clips = jarr(track["clips"])
            clips.append(.object(newClip))
            track["clips"] = .array(clips)
            report.newClips += 1
        }
        var sortedClips = jarr(track["clips"])
        sortedClips = stableSorted(sortedClips) { jnum($0.asObject ?? JSONObject(), "start") < jnum($1.asObject ?? JSONObject(), "start") }
        track["clips"] = .array(sortedClips)

        // 3) 写入过门音符(确定性 jitter:randomAt(seed, "trackId/beat"))
        var noteList = jarr(track["notes"])
        for beat in positions {
            let clip = clipAt(track, beat)
            let duration = instrument == "hat" ? 0.0625 : 0.125
            guard let clip = clip, beat + duration <= min(end, jnum(clip, "start") + jnum(clip, "length", 4)) + EPS else {
                throw SproutError("过门音符跨出音块边缘，请先调整音块，不会自动缩短")
            }
            _ = clip
            let accent: Double = beat.truncatingRemainder(dividingBy: 1) == 0 ? 1 : 0.76
            let base = instrument == "hat" ? 92.0 : 118.0
            let jitter = ((randomAt(seed: c.seed, key: "\(trackId)/\(jsNumber(beat))") - 0.5) * 8).rounded()
            var n = JSONObject()
            n["id"] = .string(jsUid())
            n["pitch"] = .number(pitch)
            n["start"] = .number(beat)
            n["duration"] = .number(duration)
            n["velocity"] = .number(max(1, min(127, (base * Double(c.energy) / 100 * accent).rounded() + jitter)))
            noteList.append(.object(n))
            report.addedNotes += 1
        }
        track["notes"] = .array(stableSorted(noteList) { a, b in
            let sa = jnum(a.asObject ?? JSONObject(), "start"), sb = jnum(b.asObject ?? JSONObject(), "start")
            if sa != sb { return sa < sb }
            return jnum(a.asObject ?? JSONObject(), "pitch") < jnum(b.asObject ?? JSONObject(), "pitch")
        })

        // 4) 共享 Pattern 签名变化 → 解除关联
        let newClipsNow = jarr(track["clips"]).compactMap(jobj)
        let oldClips = jarr(old["clips"]).compactMap(jobj)
        var detachIds: [String] = []
        for clip in newClipsNow {
            guard clip.has("patternId"), let clipId = clip["id"]?.asString,
                  let previous = oldClips.first(where: { $0["id"]?.asString == clipId }) else { continue }
            let sigNew = notesSignature(notesInClip(track, clip), origin: 0, includeId: true)
            let sigOld = notesSignature(notesInClip(old, previous), origin: 0, includeId: true)
            if sigNew != sigOld { detachIds.append(clipId) }
        }
        if !detachIds.isEmpty {
            var clipsFinal: [JSONValue] = []
            for cv in jarr(track["clips"]) {
                if var c2 = jobj(cv), detachIds.contains(c2["id"]?.asString ?? "") {
                    c2["patternId"] = nil
                    report.detached += 1
                    clipsFinal.append(.object(c2))
                } else {
                    clipsFinal.append(cv)
                }
            }
            track["clips"] = .array(clipsFinal)
        }

        guard jarr(track["notes"]).count <= 4000, jarr(track["clips"]).count <= 256 else {
            throw SproutError("过门超过每轨 4000 音符 / 256 音块上限")
        }
        tracksOut.append(.object(track))
    }
    out["tracks"] = .array(tracksOut)

    let totalNotes = jarr(out["tracks"]).reduce(0) { $0 + jarr(jobj($1)?["notes"]).count }
    guard totalNotes <= Tables.shared.maxProjectNotes else { throw SproutError("过门超过全工程 12000 音符上限") }
    try ensureClips(&out, strict: true)
    let next = try validateProject(.object(out))
    if serializeProject(next).utf8.count > VaultLimits.projectBytes {
        throw SproutError("过门后工程超过 3 MB 保存上限，没有修改音乐")
    }
    return (next, report)
}

// MARK: - 段落复制/移动/清空(sections.js planSection + sliceNote/sliceClip)

private func sliceNote(_ n: JSONObject, _ a: Double, _ b: Double, fresh: Bool, used: inout Set<String>) throws -> JSONObject? {
    let noteStart = jnum(n, "start")
    let stop0 = noteStart + jnum(n, "duration", 0.125)
    let start = max(noteStart, a)
    let stop = min(stop0, b)
    if stop <= start + EPS { return nil }
    if stop - start < 0.03125 - EPS {
        throw SproutError("段落切点产生过短音符，无法完整保留片段，请调整段落边界")
    }
    var out = n
    let id = n["id"]?.asString ?? ""
    out["id"] = .string(fresh || used.contains(id) ? jsUid() : id)
    out["start"] = .number(round4(start))
    out["duration"] = .number(round4(stop - start))
    used.insert(id)
    if out.has("timingOffset") {
        let dur = jnum(out, "duration")
        let offset = round4(max(a - start, min(jnum(out, "timingOffset"), b - start - dur)))
        out["timingOffset"] = .number(offset)
    }
    return out
}

private struct SlicedPart {
    var clip: JSONObject
    var notes: [JSONObject]
    var limitedTiming: Int
}

private func sliceClip(_ track: JSONObject, _ clip: JSONObject, _ a: Double, _ b: Double,
                       patterns: [JSONObject], fresh: Bool, used: inout Set<String>,
                       linked: Bool = false, wholeMove: Bool = false) throws -> SlicedPart {
    if b - a < 0.25 - EPS { throw SproutError("段落切点产生过短音块，请调整段落边界") }
    let cs = jnum(clip, "start"), cl = jnum(clip, "length", 4)
    let whole = abs(a - cs) < EPS && abs(b - (cs + cl)) < EPS
    var next = clip
    next["id"] = .string(fresh ? jsUid() : (clip["id"]?.asString ?? jsUid()))
    next["start"] = .number(round4(a))
    next["length"] = .number(round4(b - a))
    if !whole || (!linked && !wholeMove) { next["patternId"] = nil }
    var limitedTiming = 0
    var notes: [JSONObject] = []
    for n in notesInClip(track, clip) {
        if let part = try sliceNote(n, a, b, fresh: fresh, used: &used) {
            if jnum(part, "timingOffset") != jnum(n, "timingOffset") { limitedTiming += 1 }
            notes.append(part)
        }
    }
    if next.has("patternId"), fresh, let pid = next["patternId"]?.asString,
       let pattern = patterns.first(where: { $0["id"]?.asString == pid }) {
        notes = materializedNotes(pattern: pattern, clip: next)
    }
    return SlicedPart(clip: next, notes: notes, limitedTiming: limitedTiming)
}

public struct SectionOpReport {
    public var tracks = 0
    public var clips = 0
    public var crossingClips = 0
    public var crossingNotes = 0
    public var linkedCopies = 0
    public var detached = 0
    public var limitedTiming = 0
    public var addedNotes = 0
    public var removedNotes = 0
    public var extended = false
}

public func planSection(_ project: JSONObject, sectionId: String, action: String,
                        start: Double? = nil, linked: Bool = false, extend: Bool = false,
                        name: String? = nil) throws -> (project: JSONObject, sectionId: String?, clipIds: [String], report: SectionOpReport) {
    let before = try validateProject(.object(project))
    let section = try sectionAt(before, sectionId)
    let a = jnum(section, "start")
    let b = a + jnum(section, "length", 4)
    var out = before
    var report = SectionOpReport()

    guard ["copy", "move", "clear", "label-delete"].contains(action) else {
        throw SproutError("段落操作不正确")
    }
    if action == "label-delete" {
        out["sections"] = .array(jarr(out["sections"]).filter { jobj($0)?["id"]?.asString != sectionId })
        if jarr(out["sections"]).isEmpty { out["sections"] = nil }
        return (out, nil, [], report)
    }

    var targetStart: Double = 0
    if action != "clear" {
        guard let s = start, jsIsInteger(s), s >= 0, Int(s) % 4 == 0 else {
            throw SproutError("目标起点须是完整小节")
        }
        targetStart = s
        if a < targetStart + (b - a) - EPS && targetStart < b - EPS {
            throw SproutError("源段落与目标范围不能重叠")
        }
        let need = targetStart + (b - a)
        if need > jnum(out, "bars", 4) * 4 {
            if !extend { throw SproutError("目标超出工程，可明确选择延长为留白") }
            out["bars"] = .number(try expandedBars(need, current: jnum(out, "bars", 4)))
            report.extended = true
        }
        var target = section
        target["id"] = .string(action == "copy" ? jsUid() : (section["id"]?.asString ?? jsUid()))
        if let name = name {
            target["name"] = .string(jsSlice16(name, 40))
        } else if action == "copy" {
            target["name"] = .string(jsSlice16((section["name"]?.asString ?? "段落") + " · 副本", 40))
        }
        target["start"] = .number(targetStart)
        let kept = jarr(out["sections"]).filter { action == "copy" || jobj($0)?["id"]?.asString != sectionId }
        out["sections"] = .array(try normalizeSections(.array(kept + [.object(target)]), jnum(out, "bars", 4) * 4))
        // 目标范围已有音块则拒绝
        for t in jarr(before["tracks"]).compactMap(jobj) {
            for c in jarr(t["clips"]).compactMap(jobj) {
                let cs = jnum(c, "start"), cl = jnum(c, "length", 4)
                if cs < targetStart + (b - a) - EPS && targetStart < cs + cl - EPS {
                    throw SproutError("目标范围已有音块，不能覆盖。请先移走，或换一个空白位置")
                }
            }
        }
    }

    let patterns = jarr(before["patterns"]).compactMap(jobj)
    let beforeTracks = jarr(before["tracks"]).compactMap(jobj)
    var movedIds: [String] = []
    var tracksOut: [JSONValue] = []
    for tv in jarr(out["tracks"]) {
        guard var track = jobj(tv), let trackId = track["id"]?.asString,
              let source = beforeTracks.first(where: { $0["id"]?.asString == trackId }) else {
            tracksOut.append(tv)
            continue
        }
        let hit = jarr(source["clips"]).compactMap(jobj).filter { c in
            let cs = jnum(c, "start"), cl = jnum(c, "length", 4)
            return cs < b - EPS && a < cs + cl - EPS
        }
        if hit.isEmpty { tracksOut.append(tv); continue }
        report.tracks += 1
        report.clips += hit.count
        var retained: [SlicedPart] = []
        var pieces: [SlicedPart] = []
        var used = Set<String>()
        let hitIds = Set(hit.map { $0["id"]?.asString ?? "" })
        for clip in jarr(source["clips"]).compactMap(jobj) {
            if !hitIds.contains(clip["id"]?.asString ?? "") {
                retained.append(SlicedPart(clip: clip, notes: notesInClip(source, clip), limitedTiming: 0))
                continue
            }
            let cs = jnum(clip, "start"), cl = jnum(clip, "length", 4)
            let left = max(a, cs), right = min(b, cs + cl)
            let whole = left == cs && right == cs + cl
            if !whole { report.crossingClips += 1 }
            for n in notesInClip(source, clip) {
                let ns = jnum(n, "start"), nd = jnum(n, "duration", 0.125)
                if (ns < left - EPS && ns + nd > left + EPS) || (ns < right - EPS && ns + nd > right + EPS) {
                    report.crossingNotes += 1
                }
            }
            if action == "copy" {
                retained.append(SlicedPart(clip: clip, notes: notesInClip(source, clip), limitedTiming: 0))
            } else {
                var first = true
                for (lo, hi) in [(cs, left), (right, cs + cl)] {
                    if hi > lo + EPS {
                        var part = try sliceClip(source, clip, lo, hi, patterns: patterns, fresh: false, used: &used)
                        if !first { part.clip["id"] = .string(jsUid()) }
                        first = false
                        if clip.has("patternId") && !part.clip.has("patternId") { report.detached += 1 }
                        report.limitedTiming += part.limitedTiming
                        retained.append(part)
                    }
                }
            }
            if action != "clear" {
                var part = try sliceClip(source, clip, left, right, patterns: patterns,
                                         fresh: action == "copy" || !whole,
                                         used: &used,
                                         linked: action == "copy" && linked,
                                         wholeMove: action == "move" && whole)
                if part.clip.has("patternId") && action == "copy" { report.linkedCopies += 1 }
                if clip.has("patternId") && !part.clip.has("patternId") { report.detached += 1 }
                report.limitedTiming += part.limitedTiming
                let delta = targetStart - a
                part.clip["start"] = .number(round4(jnum(part.clip, "start") + delta))
                for i in part.notes.indices {
                    part.notes[i]["start"] = .number(round4(jnum(part.notes[i], "start") + delta))
                }
                pieces.append(part)
                movedIds.append(part.clip["id"]?.asString ?? "")
            }
        }
        let all = retained + pieces
        track["clips"] = .array(all.map { .object($0.clip) })
        var flatNotes: [JSONValue] = []
        for part in all { flatNotes.append(contentsOf: part.notes.map { .object($0) }) }
        track["notes"] = .array(flatNotes)
        guard jarr(track["clips"]).count <= 256 else { throw SproutError("段落操作超过每轨 256 音块上限") }
        let oldIds = Set(jarr(source["notes"]).compactMap { jobj($0)?["id"]?.asString })
        let newIds = Set(jarr(track["notes"]).compactMap { jobj($0)?["id"]?.asString })
        report.addedNotes += newIds.subtracting(oldIds).count
        report.removedNotes += oldIds.subtracting(newIds).count
        tracksOut.append(.object(track))
    }
    out["tracks"] = .array(tracksOut)

    try ensureClips(&out, strict: false)
    let result = try validateProject(.object(out))
    let resultSectionId: String?
    if action == "copy" {
        var found: String?
        for sv in jarr(result["sections"]) {
            if let s = jobj(sv), jnum(s, "start") == targetStart { found = s["id"]?.asString; break }
        }
        resultSectionId = found
    } else {
        resultSectionId = sectionId
    }
    return (result, resultSectionId, movedIds, report)
}
