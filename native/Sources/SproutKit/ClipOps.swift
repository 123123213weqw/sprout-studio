// 音块操作:create/move/repeat/resize/update/remove/split + notesInClip。
// 对应 dist/clips.js 同名导出;克隆→改→ensureClips,错误文案一致。

import Foundation

@inline(__always)
func jarr(_ v: JSONValue?) -> [JSONValue] { v?.asArray ?? [] }

/// 公开包装(Player 侧用)。
public func jarrPublic(_ v: JSONValue?) -> [JSONValue] { v?.asArray ?? [] }

@inline(__always)
func jobj(_ v: JSONValue) -> JSONObject? { v.asObject }

public func notesInClip(_ track: JSONObject, _ clip: JSONObject) -> [JSONObject] {
    let cs = jnum(clip, "start"), cl = jnum(clip, "length", 4)
    var out: [JSONObject] = []
    for nv in jarr(track["notes"]) {
        if let n = jobj(nv) {
            let s = jnum(n, "start")
            if s >= cs - EPS && s < cs + cl - EPS { out.append(n) }
        }
    }
    return out
}

public func clipAt(_ track: JSONObject, _ beat: Double) -> JSONObject? {
    clipAt(jarr(track["clips"]).compactMap(\.asObject), beat)
}

struct ClipRef {
    let trackIndex: Int
    let clipIndex: Int
    let track: JSONObject
    let clip: JSONObject
}

func findClipRef(_ p: JSONObject, _ trackId: String, _ clipId: String) throws -> ClipRef {
    let tracks = jarr(p["tracks"])
    for (ti, tv) in tracks.enumerated() {
        guard let t = jobj(tv), t["id"]?.asString == trackId else { continue }
        let clips = jarr(t["clips"])
        for (ci, cv) in clips.enumerated() {
            if let c = jobj(cv), c["id"]?.asString == clipId {
                return ClipRef(trackIndex: ti, clipIndex: ci, track: t, clip: c)
            }
        }
    }
    throw SproutError("请先选择一个音块")
}

func spaceOk(_ track: JSONObject, _ start: Double, _ length: Double, _ end: Double, except: String?) throws {
    guard start.isFinite, length.isFinite, start >= 0, length >= 0.25, start + length <= end + EPS else {
        throw SproutError("音块超出工程范围")
    }
    for cv in jarr(track["clips"]) {
        guard let c = jobj(cv), c["id"]?.asString != except else { continue }
        let cs = jnum(c, "start"), cl = jnum(c, "length", 4)
        if start < cs + cl - EPS && start + length > cs + EPS {
            throw SproutError("这里已有音块。先移走或删除它。")
        }
    }
}

public func expandedBars(_ end: Double, current currentArg: Double) throws -> Double {
    for b in Tables.shared.barLengths where b >= currentArg && b * 4 >= end - 0.00005 {
        return b
    }
    throw SproutError("超过 64 小节工程上限")
}

/// 通用落盘:替换 track 内容后 ensureClips。
func writeBack(_ p: inout JSONObject, trackIndex: Int, mutate: (inout JSONObject) -> Void) throws {
    var tracks = jarr(p["tracks"])
    guard var track = jobj(tracks[trackIndex]) else { throw SproutError("轨道不存在") }
    mutate(&track)
    tracks[trackIndex] = .object(track)
    p["tracks"] = .array(tracks)
    try ensureClips(&p, strict: false)
}

// MARK: - createClip

public func createClip(_ project: JSONObject, trackId: String, start: Double, length: Double = 4) throws -> (project: JSONObject, clipId: String) {
    var out = project
    try ensureClips(&out, strict: false)
    let end = jnum(out, "bars", 4) * 4
    let tracks = jarr(out["tracks"])
    guard let ti = tracks.firstIndex(where: { jobj($0)?["id"]?.asString == trackId }),
          let track = jobj(tracks[ti]) else {
        throw SproutError("轨道不存在")
    }
    try spaceOk(track, start, length, end, except: nil)
    guard jarr(track["clips"]).count < 256 else { throw SproutError("这条轨道的音块已满") }
    let clipId = jsUid()
    try writeBack(&out, trackIndex: ti) { t in
        var clip = JSONObject()
        clip["id"] = .string(clipId)
        clip["name"] = t["name"] ?? .string("音块")
        clip["start"] = .number(round4(start))
        clip["length"] = .number(round4(length))
        clip["muted"] = .bool(false)
        var clips = jarr(t["clips"])
        clips.append(.object(clip))
        t["clips"] = .array(clips)
    }
    return (out, clipId)
}

// MARK: - moveClip

public func moveClip(_ project: JSONObject, trackId: String, clipId: String, to start: Double, duplicate: Bool = false) throws -> (project: JSONObject, clipId: String) {
    var out = project
    try ensureClips(&out, strict: false)
    let end = jnum(out, "bars", 4) * 4
    let ref = try findClipRef(out, trackId, clipId)
    let notes = notesInClip(ref.track, ref.clip)
    let clipLength = jnum(ref.clip, "length", 4)
    let clipStart = jnum(ref.clip, "start")
    try spaceOk(ref.track, start, clipLength, end, except: duplicate ? nil : clipId)
    let offset = round4(start - clipStart)

    if duplicate {
        let newId = jsUid()
        try writeBack(&out, trackIndex: ref.trackIndex) { track in
            guard jarr(track["clips"]).count < 256 else { return }
            var next = ref.clip
            next["id"] = .string(newId)
            next["start"] = .number(round4(start))
            next["patternId"] = nil
            let name = (ref.clip["name"]?.asString ?? "音块") + " 副本"
            next["name"] = .string(jsSlice16(name, 40))
            var clips = jarr(track["clips"])
            clips.append(.object(next))
            track["clips"] = .array(clips)
            var noteList = jarr(track["notes"])
            for n in notes {
                var copy = n
                copy["id"] = .string(jsUid())
                copy["start"] = .number(round4(jnum(n, "start") + offset))
                noteList.append(.object(copy))
            }
            track["notes"] = .array(noteList)
        }
        return (out, newId)
    }

    try writeBack(&out, trackIndex: ref.trackIndex) { track in
        var clips = jarr(track["clips"])
        if let ci = clips.firstIndex(where: { jobj($0)?["id"]?.asString == clipId }) {
            var moved = ref.clip
            moved["start"] = .number(round4(start))
            clips[ci] = .object(moved)
        }
        track["clips"] = .array(clips)
        var noteList = jarr(track["notes"])
        for n in notes {
            if let i = noteList.firstIndex(where: { jobj($0)?["id"]?.asString == n["id"]?.asString }) {
                var copy = n
                copy["start"] = .number(round4(jnum(n, "start") + offset))
                noteList[i] = .object(copy)
            }
        }
        track["notes"] = .array(noteList)
    }
    return (out, clipId)
}

// MARK: - repeatClip

public func repeatClip(_ project: JSONObject, trackId: String, clipId: String, count: Int, start: Double? = nil, gap: Double = 0, extend: Bool = false) throws -> (project: JSONObject, clipIds: [String], addedNotes: Int, extended: Bool) {
    var out = project
    try ensureClips(&out, strict: false)
    let ref = try findClipRef(out, trackId, clipId)
    let source = notesInClip(ref.track, ref.clip)
    guard count >= 1, count <= 32, gap.isFinite, gap >= 0, gap <= 64 else {
        throw SproutError("复制数量须为 1–32，间隔不能小于零")
    }
    let clipLength = jnum(ref.clip, "length", 4)
    let clipStart = jnum(ref.clip, "start")
    let from = start ?? (clipStart + clipLength)
    guard from.isFinite, from >= 0 else { throw SproutError("复制起点不正确") }
    var positions: [Double] = []
    for i in 0..<count { positions.append(round4(from + Double(i) * (clipLength + gap))) }
    let requiredEnd = positions[positions.count - 1] + clipLength
    if requiredEnd > jnum(out, "bars", 4) * 4 + EPS {
        if !extend { throw SproutError("复制会超出工程。可选择延长工程，新增部分仅留空白") }
        out["bars"] = .number(try expandedBars(requiredEnd, current: jnum(out, "bars", 4)))
    }
    let newEnd = jnum(out, "bars", 4) * 4
    let trackNotes = jarr(ref.track["notes"]).count
    let projectNotes = jarr(out["tracks"]).reduce(0) { $0 + jarr(jobj($1)?["notes"]).count }
    guard jarr(ref.track["clips"]).count + count <= 256,
          trackNotes + source.count * count <= 4000,
          projectNotes + source.count * count <= Tables.shared.maxProjectNotes else {
        throw SproutError("复制超过音块或音符容量上限")
    }
    var newIds: [String] = []
    for (i, at) in positions.enumerated() {
        try spaceOk(ref.track, at, clipLength, newEnd, except: clipId)
        let nid = jsUid()
        newIds.append(nid)
        let currentRef = try findClipRef(out, trackId, clipId)
        try writeBack(&out, trackIndex: currentRef.trackIndex) { track in
            var next = ref.clip
            next["id"] = .string(nid)
            next["start"] = .number(at)
            let name = (ref.clip["name"]?.asString ?? "音块") + " · \(i + 2)"
            next["name"] = .string(jsSlice16(name, 40))
            next["patternId"] = nil
            var clips = jarr(track["clips"])
            clips.append(.object(next))
            track["clips"] = .array(clips)
            var noteList = jarr(track["notes"])
            for n in source {
                var copy = n
                copy["id"] = .string(jsUid())
                copy["start"] = .number(round4(jnum(n, "start") - clipStart + at))
                noteList.append(.object(copy))
            }
            track["notes"] = .array(noteList)
        }
    }
    let extended = jnum(out, "bars", 4) != jnum(project, "bars", 4)
    return (out, newIds, source.count * count, extended)
}

// MARK: - resizeClip

public func resizeClip(_ project: JSONObject, trackId: String, clipId: String, to length: Double) throws -> JSONObject {
    var out = project
    try ensureClips(&out, strict: false)
    let end = jnum(out, "bars", 4) * 4
    let ref = try findClipRef(out, trackId, clipId)
    try spaceOk(ref.track, jnum(ref.clip, "start"), length, end, except: clipId)
    let clipStart = jnum(ref.clip, "start")
    let inside = Set(notesInClip(ref.track, ref.clip).map { $0["id"]?.asString ?? "" })
    try writeBack(&out, trackIndex: ref.trackIndex) { track in
        var kept: [JSONValue] = []
        for nv in jarr(track["notes"]) {
            guard let n = jobj(nv) else { kept.append(nv); continue }
            let id = n["id"]?.asString ?? ""
            if inside.contains(id) {
                if jnum(n, "start") < clipStart + length - EPS {
                    var copy = n
                    copy["duration"] = .number(round4(min(jnum(n, "duration"), clipStart + length - jnum(n, "start"))))
                    kept.append(.object(copy))
                }
            } else {
                kept.append(nv)
            }
        }
        track["notes"] = .array(kept)
        var clips = jarr(track["clips"])
        if let ci = clips.firstIndex(where: { jobj($0)?["id"]?.asString == clipId }) {
            var resized = ref.clip
            resized["length"] = .number(round4(length))
            clips[ci] = .object(resized)
        }
        track["clips"] = .array(clips)
    }
    return out
}

// MARK: - updateClip

public func updateClip(_ project: JSONObject, trackId: String, clipId: String, start: Double? = nil, length: Double? = nil, name: String? = nil, muted: Bool? = nil) throws -> JSONObject {
    var out = project
    try ensureClips(&out, strict: false)
    let end = jnum(out, "bars", 4) * 4
    let ref = try findClipRef(out, trackId, clipId)
    let newStart = start ?? jnum(ref.clip, "start")
    let newLength = length ?? jnum(ref.clip, "length", 4)
    try spaceOk(ref.track, newStart, newLength, end, except: clipId)
    let oldStart = jnum(ref.clip, "start")
    let offset = newStart - oldStart
    let inside = Set(notesInClip(ref.track, ref.clip).map { $0["id"]?.asString ?? "" })
    try writeBack(&out, trackIndex: ref.trackIndex) { track in
        var kept: [JSONValue] = []
        for nv in jarr(track["notes"]) {
            guard let n = jobj(nv) else { kept.append(nv); continue }
            let id = n["id"]?.asString ?? ""
            if inside.contains(id) {
                let oldNoteStart = jnum(n, "start")
                if oldNoteStart - oldStart < newLength - EPS {
                    var copy = n
                    copy["start"] = .number(round4(oldNoteStart + offset))
                    copy["duration"] = .number(round4(min(jnum(n, "duration"), newStart + newLength - (oldNoteStart + offset))))
                    kept.append(.object(copy))
                }
            } else {
                kept.append(nv)
            }
        }
        track["notes"] = .array(kept)
        var clips = jarr(track["clips"])
        if let ci = clips.firstIndex(where: { jobj($0)?["id"]?.asString == clipId }) {
            var updated = ref.clip
            updated["start"] = .number(round4(newStart))
            updated["length"] = .number(round4(newLength))
            updated["name"] = .string(jsSlice16(name ?? (ref.clip["name"]?.asString ?? "音块"), 40))
            updated["muted"] = .bool(muted ?? (ref.clip["muted"]?.asBool ?? false))
            clips[ci] = .object(updated)
        }
        track["clips"] = .array(clips)
    }
    return out
}

// MARK: - removeClip

public func removeClip(_ project: JSONObject, trackId: String, clipId: String) throws -> JSONObject {
    var out = project
    try ensureClips(&out, strict: false)
    let ref = try findClipRef(out, trackId, clipId)
    let inside = Set(notesInClip(ref.track, ref.clip).map { $0["id"]?.asString ?? "" })
    try writeBack(&out, trackIndex: ref.trackIndex) { track in
        track["notes"] = .array(jarr(track["notes"]).filter { nv in
            guard let n = jobj(nv) else { return true }
            return !inside.contains(n["id"]?.asString ?? "")
        })
        track["clips"] = .array(jarr(track["clips"]).filter { jobj($0)?["id"]?.asString != clipId })
    }
    return out
}

// MARK: - splitClip

public func splitClip(_ project: JSONObject, trackId: String, clipId: String, at beat: Double) throws -> (project: JSONObject, clipId: String) {
    var out = project
    try ensureClips(&out, strict: false)
    let ref = try findClipRef(out, trackId, clipId)
    let clipStart = jnum(ref.clip, "start")
    let end = clipStart + jnum(ref.clip, "length", 4)
    guard beat.isFinite, beat >= clipStart + 0.25, beat <= end - 0.25 else {
        throw SproutError("分割点须位于音块内部")
    }
    let notes = notesInClip(ref.track, ref.clip)
    let rightId = jsUid()
    try writeBack(&out, trackIndex: ref.trackIndex) { track in
        var noteList = jarr(track["notes"])
        for n in notes {
            let s = jnum(n, "start"), d = jnum(n, "duration")
            guard s < beat && s + d > beat else { continue }
            var right = n
            right["id"] = .string(jsUid())
            right["start"] = .number(round4(beat))
            right["duration"] = .number(round4(s + d - beat))
            noteList.append(.object(right))
            if let i = noteList.firstIndex(where: { jobj($0)?["id"]?.asString == n["id"]?.asString }) {
                var left = n
                left["duration"] = .number(round4(beat - s))
                noteList[i] = .object(left)
            }
        }
        track["notes"] = .array(noteList)
        var clips = jarr(track["clips"])
        var rightClip = ref.clip
        rightClip["id"] = .string(rightId)
        rightClip["start"] = .number(round4(beat))
        rightClip["length"] = .number(round4(end - beat))
        rightClip["name"] = .string(jsSlice16((ref.clip["name"]?.asString ?? "音块") + " · B", 40))
        clips.append(.object(rightClip))
        if let ci = clips.firstIndex(where: { jobj($0)?["id"]?.asString == clipId }) {
            var leftClip = ref.clip
            leftClip["length"] = .number(round4(beat - clipStart))
            clips[ci] = .object(leftClip)
        }
        track["clips"] = .array(clips)
    }
    return (out, rightId)
}
