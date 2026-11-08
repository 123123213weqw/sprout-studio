// Pattern 库:normalizePatterns / 实例化 / 签名 / synchronizePatterns。
// 对应 dist/patterns-core.js;link_* 音符 ID 是 FNV-1a 64,必须与 JS 逐位一致。

// MARK: - FNV-1a 64(对应 JS BigInt.asUintN(64) 版本)

public func instanceNoteId(_ clipId: String, _ patternId: String, _ noteId: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for u in "\(clipId)/\(patternId)/\(noteId)".utf16 {
        hash ^= UInt64(u)
        hash = hash &* 0x100000001b3
    }
    let hex = String(hash, radix: 16)
    return "link_" + String(repeating: "0", count: 16 - hex.count) + hex
}

// MARK: - normalizePatterns

func normalizePatterns(_ input: JSONValue) throws -> [JSONValue] {
    let limits = Tables.shared.patternLimits
    guard let list = input.asArray, list.count <= limits.patterns else {
        throw SproutError("Pattern 库最多支持 64 个乐句")
    }
    var total = 0
    var ids = Set<String>()
    var out: [JSONValue] = []
    for pv in list {
        guard let pattern = pv.asObject,
              let id = pattern["id"]?.asString, jsSafeId(id), !ids.contains(id),
              let instrument = pattern["instrument"]?.asString,
              let meta = Tables.shared.instruments[instrument],
              let rawLength = pattern["length"]?.asNumber, jsIsFinite(rawLength),
              rawLength >= 0.25, rawLength <= Tables.shared.maxBeats,
              let noteList = pattern["notes"]?.asArray, noteList.count <= limits.perPattern else {
            throw SproutError("Pattern 数据、标识或长度不正确")
        }
        ids.insert(id)
        let length = round4(rawLength)
        var noteIds = Set<String>()
        var notes: [JSONObject] = []
        for nv in noteList {
            guard let n = nv.asObject else { throw SproutError("Pattern 音符不合法") }
            let idRaw: String? = n["id"]?.asString
            let pitchRaw: Double? = n["pitch"]?.asNumber
            let startRaw: Double? = n["start"]?.asNumber
            let durationRaw: Double? = n["duration"]?.asNumber
            let velocityRaw: Double? = n["velocity"]?.asNumber
            guard let nid = idRaw, let pitch = pitchRaw, let start = startRaw,
                  let duration = durationRaw, let velocity = velocityRaw else {
                throw SproutError("Pattern 音符不合法")
            }
            let idOk: Bool = jsSafeId(nid) && !noteIds.contains(nid)
            let pitchOk: Bool = jsIsInteger(pitch) && pitch >= 24 && pitch <= 108
                && !(meta.kind == "drum" && pitch != Double(meta.pitch ?? -1))
            let spanOk: Bool = jsIsFinite(start) && start >= 0
                && jsIsFinite(duration) && duration >= 0.03125 && start + duration <= length + EPS
            let velOk: Bool = jsIsFinite(velocity) && velocity >= 1 && velocity <= 127
            guard idOk, pitchOk, spanOk, velOk else { throw SproutError("Pattern 音符不合法") }
            noteIds.insert(nid)
            var note = JSONObject()
            note["id"] = .string(nid)
            note["pitch"] = .number(pitch)
            note["start"] = .number(round4(start))
            note["duration"] = .number(round4(duration))
            note["velocity"] = .number(velocity.rounded(.toNearestOrAwayFromZero))
            if let d = note["duration"]?.asNumber, let s = note["start"]?.asNumber,
               d < 0.03125 || s + d > length + EPS {
                throw SproutError("Pattern 音符舍入后越界")
            }
            if n.has("timingOffset") {
                guard let to = n["timingOffset"]?.asNumber, jsIsFinite(to), abs(to) <= 0.04,
                      start + to >= -EPS, start + to + duration <= length + EPS else {
                    throw SproutError("Pattern 微时间偏移越界")
                }
                note["timingOffset"] = .number(round4(to))
                if let s = note["start"]?.asNumber, let d = note["duration"]?.asNumber,
                   let nto = note["timingOffset"]?.asNumber,
                   s + nto < -EPS || s + nto + d > length + EPS {
                    throw SproutError("Pattern 微时间偏移舍入后越界")
                }
            }
            notes.append(note)
        }
        // 完整三级决胜(起点、音高、ID),无需稳定排序;ID 按 UTF-16 序即码点序
        notes.sort { a, b in
            let sa = a["start"]?.asNumber ?? 0, sb = b["start"]?.asNumber ?? 0
            if sa != sb { return sa < sb }
            let pa = a["pitch"]?.asNumber ?? 0, pb = b["pitch"]?.asNumber ?? 0
            if pa != pb { return pa < pb }
            return (a["id"]?.asString ?? "") < (b["id"]?.asString ?? "")
        }
        total += notes.count
        if total > limits.notes { throw SproutError("Pattern 库音符超过 12000 上限") }
        var p = JSONObject()
        p["id"] = .string(id)
        p["name"] = .string(jsStringField(pattern["name"], fallback: "未命名乐句", limit: 60))
        p["instrument"] = .string(instrument)
        p["kind"] = .string(meta.kind)
        p["length"] = .number(length)
        p["notes"] = .array(notes.map { .object($0) })
        out.append(.object(p))
    }
    return out
}

// MARK: - 实例化与签名

func materializedNotes(pattern: JSONObject, clip: JSONObject) -> [JSONObject] {
    let clipId = clip["id"]?.asString ?? ""
    let patternId = pattern["id"]?.asString ?? ""
    let clipStart = clip["start"]?.asNumber ?? 0
    let notes = pattern["notes"]?.asArray ?? []
    return notes.compactMap { nv in
        guard let n = nv.asObject else { return nil }
        var m = JSONObject()
        m["id"] = .string(instanceNoteId(clipId, patternId, n["id"]?.asString ?? ""))
        m["pitch"] = n["pitch"] ?? .null
        m["start"] = .number(round4(clipStart + (n["start"]?.asNumber ?? 0)))
        m["duration"] = n["duration"] ?? .null
        m["velocity"] = n["velocity"] ?? .null
        if n.has("timingOffset") { m["timingOffset"] = n["timingOffset"]! }
        return m
    }
}

/// JSON.stringify(紧凑) 的音符投影,排序后以 | 连接;includeId 对应 strict 模式。
func notesSignature(_ notes: [JSONObject], origin: Double, includeId: Bool) -> String {
    notes.map { n in
        var o = JSONObject()
        if includeId { o["id"] = n["id"] ?? .null }
        o["pitch"] = n["pitch"] ?? .null
        o["start"] = .number(round4((n["start"]?.asNumber ?? 0) - origin))
        o["duration"] = .number(round4(n["duration"]?.asNumber ?? 0))
        o["velocity"] = .number((n["velocity"]?.asNumber ?? 0).rounded(.toNearestOrAwayFromZero))
        o["timingOffset"] = .number(round4(n["timingOffset"]?.asNumber ?? 0))
        return jsCompactStringify(.object(o))
    }.sorted().joined(separator: "|")
}

// MARK: - synchronizePatterns

func synchronizePatterns(_ project: inout JSONObject, strict: Bool) throws {
    let tracksRaw = project["tracks"]?.asArray ?? []
    if !project.has("patterns") {
        for tv in tracksRaw {
            for cv in (tv.asObject?["clips"]?.asArray ?? []) where cv.asObject?.has("patternId") == true {
                throw SproutError("共享音块缺少 Pattern 库")
            }
        }
        return
    }
    let patterns = try normalizePatterns(project["patterns"]!)
    project["patterns"] = .array(patterns)
    var patternMap: [String: JSONObject] = [:]
    for pv in patterns { if let p = pv.asObject, let id = p["id"]?.asString { patternMap[id] = p } }

    var tracks = tracksRaw
    for ti in tracks.indices {
        guard var track = tracks[ti].asObject else { continue }
        var clips = track["clips"]?.asArray ?? []
        var notes = track["notes"]?.asArray ?? []
        for ci in clips.indices {
            guard var clip = clips[ci].asObject, clip.has("patternId") else { continue }
            guard let pid = clip["patternId"]?.asString, jsSafeId(pid), let pattern = patternMap[pid] else {
                throw SproutError("共享音块引用了不存在的 Pattern")
            }
            let pKind = pattern["kind"]?.asString ?? ""
            let tKind = track["kind"]?.asString ?? ""
            guard pKind == tKind, pKind != "drum" || pattern["instrument"]?.asString == track["instrument"]?.asString else {
                throw SproutError("Pattern 与轨道音源不兼容")
            }
            let clipStart = clip["start"]?.asNumber ?? 0
            let clipLength = clip["length"]?.asNumber ?? 0
            let existing = notes.compactMap { nv -> JSONObject? in
                guard let o = nv.asObject, let s = o["start"]?.asNumber else { return nil }
                return s >= clipStart - EPS && s < clipStart + clipLength - EPS ? o : nil
            }
            let expected = materializedNotes(pattern: pattern, clip: clip)
            let patternLength = pattern["length"]?.asNumber ?? 0
            let same = abs(clipLength - patternLength) <= EPS
                && notesSignature(existing, origin: clipStart, includeId: strict)
                    == notesSignature(expected, origin: clipStart, includeId: strict)
            if !same {
                if strict { throw SproutError("共享 Pattern 与音块缓存不一致，拒绝恢复") }
                clip["patternId"] = nil
                clips[ci] = .object(clip)
                continue
            }
            let existingIds = Set(existing.map { $0["id"]?.asString ?? "" })
            var merged = notes.filter { nv in
                guard let o = nv.asObject else { return true }
                return !existingIds.contains(o["id"]?.asString ?? "")
            }
            merged.append(contentsOf: expected.map { .object($0) })
            notes = stableSorted(merged) { a, b in
                let sa = a.asObject?["start"]?.asNumber ?? 0, sb = b.asObject?["start"]?.asNumber ?? 0
                if sa != sb { return sa < sb }
                let pa = a.asObject?["pitch"]?.asNumber ?? 0, pb = b.asObject?["pitch"]?.asNumber ?? 0
                return pa < pb
            }
            clips[ci] = .object(clip)
        }
        track["clips"] = .array(clips)
        track["notes"] = .array(notes)
        tracks[ti] = .object(track)
    }
    project["tracks"] = .array(tracks)

    var seen = Set<String>()
    for tv in tracks {
        for nv in (tv.asObject?["notes"]?.asArray ?? []) {
            if let id = nv.asObject?["id"]?.asString {
                if seen.contains(id) { throw SproutError("Pattern 实例音符标识碰撞") }
                seen.insert(id)
            }
        }
    }
    project["version"] = .number(3)
}

// MARK: - 紧凑 JSON(签名用)

public func jsCompactStringify(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let d): return jsNumber(d)
    case .string(let s): return jsQuote(s)
    case .array(let items): return "[" + items.map(jsCompactStringify).joined(separator: ",") + "]"
    case .object(let obj):
        return "{" + obj.pairs.map { jsQuote($0.0) + ":" + jsCompactStringify($0.1) }.joined(separator: ",") + "}"
    }
}
