// 移调与长度调整:对应 dist/music.js 的 transposeProject 与
// clips.js 的 resizeClipProject(fill='repeat' 重复铺满 / 'blank' 留空)。
// 纯函数,输出经 ensureClips;错误文案沿用。

import Foundation

public func transposeProject(_ input: JSONObject, toKey newKey: String) throws -> JSONObject {
    guard let oldKey = Tables.shared.keys[input["key"]?.asString ?? ""],
          let next = Tables.shared.keys[newKey] else {
        throw SproutError("无效调性")
    }
    var p = input
    var tracks: [JSONValue] = []
    for tv in (p["tracks"]?.asArray ?? []) {
        guard var t = tv.asObject else { tracks.append(tv); continue }
        guard t["kind"]?.asString != "drum" else { tracks.append(tv); continue }
        var notes: [JSONValue] = []
        for nv in (t["notes"]?.asArray ?? []) {
            guard var n = nv.asObject else { notes.append(nv); continue }
            let pitch = jnum(n, "pitch")
            let delta = Int(pitch - Double(oldKey.root))
            let octave = Int(floor(Double(delta) / 12))
            let pc = ((delta % 12) + 12) % 12
            var deg = 0
            for i in 1...6 {
                if abs(Int(oldKey.scale[i]) - pc) < abs(Int(oldKey.scale[deg]) - pc) { deg = i }
            }
            let mapped: Double = Double(next.root) + Double(12 * octave) + next.scale[deg]
            let clamped: Double = clamp(mapped, 24, 108)
            n["pitch"] = .number(clamped)
            notes.append(.object(n))
        }
        t["notes"] = .array(notes)
        tracks.append(.object(t))
    }
    p["tracks"] = .array(tracks)
    p["key"] = .string(newKey)
    var result = p
    try ensureClips(&result, strict: false)
    return result
}

public func resizeProject(_ input: JSONObject, toBars bars: Double, fill: String = "repeat") throws -> JSONObject {
    guard validBars(bars), fill == "blank" || fill == "repeat" else {
        throw SproutError("工程长度或扩展方式不正确")
    }
    var out = input
    let oldEnd = jnum(out, "bars", 4) * 4
    let end = bars * 4
    var tracks: [JSONValue] = []
    for tv in (out["tracks"]?.asArray ?? []) {
        guard var t = tv.asObject else { tracks.append(tv); continue }
        let clipsIn = (t["clips"]?.asArray ?? []).compactMap(\.asObject)
        let notesIn = (t["notes"]?.asArray ?? []).compactMap(\.asObject)

        var clips: [JSONValue] = t["clips"]?.asArray ?? []
        var notes: [JSONValue] = t["notes"]?.asArray ?? []
        if end > oldEnd, fill == "repeat" {
            var offset = oldEnd
            while offset < end {
                for c in clipsIn where jnum(c, "start") + offset < end {
                    var next = c
                    next["id"] = .string(jsUid())
                    next["start"] = .number(jnum(c, "start") + offset)
                    next["length"] = .number(min(jnum(c, "length"), end - jnum(c, "start") - offset))
                    next["patternId"] = nil
                    clips.append(.object(next))
                }
                for n in notesIn where jnum(n, "start") + offset < end {
                    var next = n
                    next["id"] = .string(jsUid())
                    next["start"] = .number(jnum(n, "start") + offset)
                    next["duration"] = .number(min(jnum(n, "duration"), end - jnum(n, "start") - offset))
                    notes.append(.object(next))
                }
                offset += oldEnd
            }
        }
        // 收缩:丢出界音块,夹长度;音符按所属音块过滤并夹长度
        var keptClips: [JSONValue] = []
        for cv in clips {
            guard let c = cv.asObject else { continue }
            guard jnum(c, "start") < end - 0.25 + EPS else { continue }
            var clipped = c
            clipped["length"] = .number(min(jnum(c, "length"), end - jnum(c, "start")))
            keptClips.append(.object(clipped))
        }
        clips = keptClips
        let clipIndex = clips.compactMap(\.asObject)
        var keptNotes: [JSONValue] = []
        for nv in notes {
            guard let n = nv.asObject else { continue }
            let start = jnum(n, "start")
            guard start < end - 0.03125 + EPS,
                  clipAt(clipIndex, start) != nil else { continue }
            var clipped = n
            clipped["duration"] = .number(min(jnum(n, "duration"), end - start))
            keptNotes.append(.object(clipped))
        }
        t["clips"] = .array(clips)
        t["notes"] = .array(keptNotes)
        tracks.append(.object(t))
    }
    out["tracks"] = .array(tracks)
    if let range = out["loopRange"]?.asObject {
        let start = jnum(range, "start")
        if start >= end - 0.25 + EPS {
            out["loopRange"] = nil
        } else {
            var clipped = range
            clipped["end"] = .number(min(jnum(range, "end"), end))
            out["loopRange"] = .object(clipped)
        }
    }
    out["bars"] = .number(bars)
    // resizeSections:过滤出界、裁短,再走 normalizeSections(对齐失败即抛错,与 JS 一致)
    if let sections = out["sections"]?.asArray {
        let kept = sections.compactMap { sv -> JSONValue? in
            guard let s = sv.asObject else { return nil }
            let start = jnum(s, "start")
            guard start < end else { return nil }
            var next = s
            next["length"] = .number(min(jnum(s, "length"), end - start))
            return .object(next)
        }
        let normalized = try normalizeSections(.array(kept), end)
        out["sections"] = .array(normalized)
    }
    var result = out
    try ensureClips(&result, strict: false)
    return result
}
