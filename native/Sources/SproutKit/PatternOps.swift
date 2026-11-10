// Pattern CRUD:capture/place/link/detach/update/remove + 实例查询。
// 对应 dist/patterns.js;输出经 validateProject。

import Foundation

public struct PatternInstance {
    public let trackId: String
    public let trackName: String
    public let clipId: String
    public let clipName: String
    public let start: Double
    public let length: Double
    public let muted: Bool
}

public func patternInstances(_ project: JSONObject, patternId: String) -> [PatternInstance] {
    var out: [PatternInstance] = []
    for tv in jarr(project["tracks"]) {
        guard let t = jobj(tv) else { continue }
        for cv in jarr(t["clips"]) {
            guard let c = jobj(cv), c["patternId"]?.asString == patternId else { continue }
            out.append(PatternInstance(
                trackId: t["id"]?.asString ?? "",
                trackName: t["name"]?.asString ?? "",
                clipId: c["id"]?.asString ?? "",
                clipName: c["name"]?.asString ?? "",
                start: jnum(c, "start"),
                length: jnum(c, "length", 4),
                muted: c["muted"]?.asBool ?? false
            ))
        }
    }
    return out
}

func findPattern(_ p: JSONObject, _ id: String) throws -> JSONObject {
    for pv in jarr(p["patterns"]) {
        if let pat = jobj(pv), pat["id"]?.asString == id { return pat }
    }
    throw SproutError("请先选择一个 Pattern")
}

func patternCompatible(_ pattern: JSONObject, _ track: JSONObject) -> Bool {
    let pKind = pattern["kind"]?.asString ?? ""
    let tKind = track["kind"]?.asString ?? ""
    guard pKind == tKind else { return false }
    if pKind == "drum" { return pattern["instrument"]?.asString == track["instrument"]?.asString }
    return true
}

/// 绑定:清块内音符 → patternId/长度对齐 → 物化。
func bindPattern(_ p: inout JSONObject, trackIndex: Int, clipIndex: Int, pattern: JSONObject) {
    var tracks = jarr(p["tracks"])
    guard var track = jobj(tracks[trackIndex]) else { return }
    var clips = jarr(track["clips"])
    guard var clip = jobj(clips[clipIndex]) else { return }
    let clipStart = jnum(clip, "start")
    let clipLength = jnum(clip, "length", 4)
    let inside = Set(notesInClip(track, clip).map { $0["id"]?.asString ?? "" })
    var noteList: [JSONValue] = []
    for nv in jarr(track["notes"]) {
        if let n = jobj(nv), !inside.contains(n["id"]?.asString ?? "") { noteList.append(nv) }
    }
    clip["patternId"] = pattern["id"] ?? .null
    clip["length"] = pattern["length"] ?? .number(clipLength)
    clips[clipIndex] = .object(clip)
    track["clips"] = .array(clips)
    for n in materializedNotes(pattern: pattern, clip: clip) {
        noteList.append(.object(n))
    }
    track["notes"] = .array(noteList)
    tracks[trackIndex] = .object(track)
    p["tracks"] = .array(tracks)
}

public func capturePattern(_ project: JSONObject, trackId: String, clipId: String, name: String? = nil, linkSource: Bool = false) throws -> (project: JSONObject, patternId: String) {
    var p = project
    try ensureClips(&p, strict: false)
    let ref = try findClipRef(p, trackId, clipId)
    let patternId = jsUid()
    let clipStart = jnum(ref.clip, "start")
    var rawNotes: [JSONValue] = []
    for n in notesInClip(ref.track, ref.clip) {
        var copy = n
        copy["id"] = .string(jsUid())
        copy["start"] = .number(round4(jnum(n, "start") - clipStart))
        rawNotes.append(.object(copy))
    }
    var raw = JSONObject()
    raw["id"] = .string(patternId)
    raw["name"] = .string(name ?? (ref.clip["name"]?.asString ?? "乐句"))
    raw["instrument"] = ref.track["instrument"] ?? .string("lead")
    raw["length"] = ref.clip["length"] ?? .number(4)
    raw["notes"] = .array(rawNotes)
    let normalized = try normalizePatterns(.array([.object(raw)]))
    guard let pattern = jobj(normalized[0]) else { throw SproutError("Pattern 数据、标识或长度不正确") }

    var patterns = jarr(p["patterns"])
    patterns.append(.object(pattern))
    p["patterns"] = .array(patterns)
    p["version"] = .number(3)
    if linkSource {
        bindPattern(&p, trackIndex: ref.trackIndex, clipIndex: ref.clipIndex, pattern: pattern)
    }
    try ensureClips(&p, strict: false)
    return (try validateProject(.object(p)), patternId)
}

public func placePattern(_ project: JSONObject, patternId: String, trackId: String, at start: Double, linked: Bool = true, extend: Bool = false) throws -> (project: JSONObject, clipId: String, extended: Bool) {
    var p = project
    try ensureClips(&p, strict: false)
    let pattern = try findPattern(p, patternId)
    let tracks = jarr(p["tracks"])
    guard let ti = tracks.firstIndex(where: { jobj($0)?["id"]?.asString == trackId }),
          let track = jobj(tracks[ti]) else {
        throw SproutError("Pattern 与目标音源不兼容；鼓只可放入同种鼓轨")
    }
    guard patternCompatible(pattern, track) else {
        throw SproutError("Pattern 与目标音源不兼容；鼓只可放入同种鼓轨")
    }
    let patternLength = jnum(pattern, "length", 4)
    guard start.isFinite, start >= 0 else { throw SproutError("放置位置或关联方式不正确") }
    if start + patternLength > jnum(p, "bars", 4) * 4 + EPS {
        if !extend { throw SproutError("放置超出工程，可明确选择空白延长") }
        p["bars"] = .number(try expandedBars(start + patternLength, current: jnum(p, "bars", 4)))
    }
    let created = try createClip(p, trackId: trackId, start: start, length: patternLength)
    var out = created.project
    let ref = try findClipRef(out, trackId, created.clipId)
    if linked {
        bindPattern(&out, trackIndex: ref.trackIndex, clipIndex: ref.clipIndex, pattern: pattern)
    } else {
        var tracks2 = jarr(out["tracks"])
        guard var t2 = jobj(tracks2[ref.trackIndex]) else { throw SproutError("音块已不存在") }
        var noteList = jarr(t2["notes"])
        for nv in jarr(pattern["notes"]) {
            guard let n = jobj(nv) else { continue }
            var copy = n
            copy["id"] = .string(jsUid())
            copy["start"] = .number(round4(start + jnum(n, "start")))
            noteList.append(.object(copy))
        }
        t2["notes"] = .array(noteList)
        tracks2[ref.trackIndex] = .object(t2)
        out["tracks"] = .array(tracks2)
    }
    // 命名:placePattern 以 pattern 名命名新块
    let ref2 = try findClipRef(out, trackId, created.clipId)
    var tracks3 = jarr(out["tracks"])
    if var t3 = jobj(tracks3[ref2.trackIndex]) {
        var clips3 = jarr(t3["clips"])
        if var c3 = jobj(clips3[ref2.clipIndex]) {
            c3["name"] = .string(jsSlice16(pattern["name"]?.asString ?? "乐句", 40))
            clips3[ref2.clipIndex] = .object(c3)
            t3["clips"] = .array(clips3)
            tracks3[ref2.trackIndex] = .object(t3)
            out["tracks"] = .array(tracks3)
        }
    }
    let extended = jnum(out, "bars", 4) != jnum(project, "bars", 4)
    try ensureClips(&out, strict: false)
    return (try validateProject(.object(out)), created.clipId, extended)
}

public func linkClipToPattern(_ project: JSONObject, patternId: String, trackId: String, clipId: String, replace: Bool = false) throws -> JSONObject {
    var p = project
    try ensureClips(&p, strict: false)
    let pattern = try findPattern(p, patternId)
    let ref = try findClipRef(p, trackId, clipId)
    guard patternCompatible(pattern, ref.track) else {
        throw SproutError("Pattern 与目标轨道不兼容")
    }
    guard abs(jnum(ref.clip, "length", 4) - jnum(pattern, "length", 4)) <= EPS else {
        throw SproutError("关联音块须与 Pattern 等长")
    }
    if !replace {
        let existing = notesInClip(ref.track, ref.clip)
        let expected = jarr(pattern["notes"]).compactMap(jobj)
        if notesSignature(existing, origin: jnum(ref.clip, "start"), includeId: false)
            != notesSignature(expected, origin: 0, includeId: false) {
            throw SproutError("当前音块内容不同。只能明确替换内容后关联")
        }
    }
    bindPattern(&p, trackIndex: ref.trackIndex, clipIndex: ref.clipIndex, pattern: pattern)
    try ensureClips(&p, strict: false)
    return try validateProject(.object(p))
}

public func detachPatternClip(_ project: JSONObject, trackId: String, clipId: String) throws -> JSONObject {
    var p = project
    try ensureClips(&p, strict: false)
    let ref = try findClipRef(p, trackId, clipId)
    var tracks = jarr(p["tracks"])
    guard var track = jobj(tracks[ref.trackIndex]) else { throw SproutError("音块已不存在") }
    var clips = jarr(track["clips"])
    guard var clip = jobj(clips[ref.clipIndex]) else { throw SproutError("音块已不存在") }
    clip["patternId"] = nil
    clips[ref.clipIndex] = .object(clip)
    track["clips"] = .array(clips)
    tracks[ref.trackIndex] = .object(track)
    p["tracks"] = .array(tracks)
    return try validateProject(.object(p))
}

public func updatePattern(_ project: JSONObject, patternId: String, name: String? = nil, length: Double? = nil, notes: [JSONObject]? = nil) throws -> (project: JSONObject, affected: Int) {
    var p = project
    try ensureClips(&p, strict: false)
    let source = try findPattern(p, patternId)
    var merged = source
    if let name = name { merged["name"] = .string(name) }
    if let length = length { merged["length"] = .number(length) }
    if let notes = notes { merged["notes"] = .array(notes.map { .object($0) }) }
    let normalized = try normalizePatterns(.array([.object(merged)]))
    guard let next = jobj(normalized[0]) else { throw SproutError("Pattern 数据、标识或长度不正确") }
    let instances = patternInstances(p, patternId: patternId)
    var patterns = jarr(p["patterns"])
    for i in patterns.indices where jobj(patterns[i])?["id"]?.asString == patternId {
        patterns[i] = .object(next)
    }
    p["patterns"] = .array(patterns)
    for instance in instances {
        if let ref = try? findClipRef(p, instance.trackId, instance.clipId) {
            bindPattern(&p, trackIndex: ref.trackIndex, clipIndex: ref.clipIndex, pattern: next)
        }
    }
    try ensureClips(&p, strict: false)
    return (try validateProject(.object(p)), instances.count)
}

public func removePattern(_ project: JSONObject, patternId: String, detach: Bool = false) throws -> JSONObject {
    var p = project
    try ensureClips(&p, strict: false)
    _ = try findPattern(p, patternId)
    let refs = patternInstances(p, patternId: patternId)
    if !refs.isEmpty && !detach {
        throw SproutError("仍有共享音块使用这个 Pattern，请先独立化或明确保留音符并解除全部关联")
    }
    for ref in refs {
        if let found = try? findClipRef(p, ref.trackId, ref.clipId) {
            var tracks = jarr(p["tracks"])
            if var track = jobj(tracks[found.trackIndex]) {
                var clips = jarr(track["clips"])
                if var clip = jobj(clips[found.clipIndex]) {
                    clip["patternId"] = nil
                    clips[found.clipIndex] = .object(clip)
                    track["clips"] = .array(clips)
                    tracks[found.trackIndex] = .object(track)
                    p["tracks"] = .array(tracks)
                }
            }
        }
    }
    p["patterns"] = .array(jarr(p["patterns"]).filter { jobj($0)?["id"]?.asString != patternId })
    return try validateProject(.object(p))
}
