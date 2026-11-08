// validateProject:.sprout 工程的唯一入口。对应 dist/music.js 的同名导出。
// 输出 key 顺序 = JS 对象插入顺序,序列化必须与 JSON.stringify(project, null, 2) 逐字节一致。

public func validateProject(_ input: JSONValue) throws -> JSONObject {
    guard let inp = input.asObject else { throw SproutError("工程格式不正确") }

    guard let bars = inp["bars"]?.asNumber, validBars(bars) else {
        throw SproutError("工程长度必须为 4、8、16、32 或 64 小节")
    }
    guard let bpm = inp["bpm"]?.asNumber, jsIsFinite(bpm), bpm >= 40, bpm <= 200 else {
        throw SproutError("速度须在 40–200 BPM 之间")
    }
    guard let key = inp["key"]?.asString, Tables.shared.keys[key] != nil else {
        throw SproutError("暂不支持这个调性")
    }
    guard let tracksIn = inp["tracks"]?.asArray, tracksIn.count >= 1, tracksIn.count <= 16 else {
        throw SproutError("轨道数量须在 1–16 之间")
    }
    let versionNum = inp["version"]?.asNumber
    let hasPatterns = inp.has("patterns")
    if (versionNum == 3 && !(inp["patterns"]?.isArray ?? false)) || (hasPatterns && versionNum != 3) {
        throw SproutError("共享 Pattern 工程须使用版本 3 和完整 Pattern 库")
    }

    var p = JSONObject()
    p["version"] = .number(versionNum == 2 ? 2 : 1)
    let id: String
    if let raw = inp["id"]?.asString, jsSafeId(raw) { id = raw } else { id = jsUid() }
    p["id"] = .string(id)
    p["name"] = .string(jsStringField(inp["name"], fallback: "未命名作品", limit: 60))
    p["style"] = .string((inp["style"]?.asString).map { Tables.shared.styleIds.contains($0) ? $0 : "lofi" } ?? "lofi")
    p["key"] = .string(key)
    p["bars"] = .number(bars)
    p["bpm"] = .number(bpm)
    p["swing"] = .number(clamp({ if let v = inp["swing"]?.asNumber, jsIsFinite(v) { return v }; return 0 }(), 0, 45))
    p["master"] = .number(clamp({ if let v = inp["master"]?.asNumber, jsIsFinite(v) { return v }; return 0.75 }(), 0, 1))
    p["seed"] = .number({ if let v = inp["seed"]?.asNumber, jsIsFinite(v) { return v }; return 1 }())
    p["tracks"] = .array([])

    if inp.has("composition"), let composition = inp["composition"] {
        p["composition"] = .object(try normalizeControls(composition, seed: p["seed"]!.asNumber!))
    }
    if inp.has("loopRange"), let loopRange = inp["loopRange"] {
        p["loopRange"] = .object(try normalizeRange(loopRange, bars * 4))
    }
    if inp.has("sections"), let sections = inp["sections"] {
        p["sections"] = .array(try normalizeSections(sections, bars * 4))
    }
    if hasPatterns {
        p["version"] = .number(3)
        p["patterns"] = inp["patterns"]!
    }

    var total = 0
    var trackIds = Set<String>()
    var noteIds = Set<String>()
    var outTracks: [JSONValue] = []
    for tv in tracksIn {
        guard let t = tv.asObject,
              let instrument = t["instrument"]?.asString,
              let meta = Tables.shared.instruments[instrument] else {
            throw SproutError("工程包含不支持的音源")
        }
        guard let notesIn = t["notes"]?.asArray, notesIn.count <= 4000 else {
            throw SproutError("轨道音符数量不正确")
        }
        let tid: String
        if let raw = t["id"]?.asString, jsSafeId(raw), !trackIds.contains(raw) { tid = raw } else { tid = jsUid() }
        trackIds.insert(tid)

        var out = JSONObject()
        out["id"] = .string(tid)
        out["instrument"] = .string(instrument)
        out["kind"] = .string(meta.kind)
        out["name"] = .string(jsStringField(t["name"], fallback: meta.name, limit: 40))
        out["color"] = .string(meta.color)
        out["volume"] = .number(clamp(jsIsFinite(t["volume"]?.asNumber ?? .nan) ? t["volume"]!.asNumber! : 0.7, 0, 1))
        out["pan"] = .number(clamp(jsIsFinite(t["pan"]?.asNumber ?? .nan) ? t["pan"]!.asNumber! : 0, -1, 1))
        out["muted"] = .bool(t["muted"]?.asBool == true)
        out["solo"] = .bool(t["solo"]?.asBool == true)
        out["notes"] = .array([])
        if t.has("clips") { out["clips"] = t["clips"]! }
        if t.has("sound") { out["sound"] = .object(try normalizeSound(instrument, t["sound"]!)) }
        if t.has("sampler") { out["sampler"] = .object(try normalizeSampler(instrument, t["sampler"]!)) }

        var outNotes: [JSONObject] = []
        for nv in notesIn {
            guard let n = nv.asObject else { throw SproutError("音符数据不合法") }
            let pitchRaw: Double? = n["pitch"]?.asNumber
            let startRaw: Double? = n["start"]?.asNumber
            let durationRaw: Double? = n["duration"]?.asNumber
            let velocityRaw: Double? = n["velocity"]?.asNumber
            guard let pitch = pitchRaw, let start = startRaw,
                  let duration = durationRaw, let velocity = velocityRaw else {
                throw SproutError("音符数据不合法")
            }
            let pitchOk: Bool = jsIsInteger(pitch) && pitch >= 24 && pitch <= 108
            let spanOk: Bool = jsIsFinite(start) && start >= 0 && start <= bars * 4 - 0.03125
                && jsIsFinite(duration) && duration >= 0.03125 && duration <= bars * 4
            let velOk: Bool = jsIsFinite(velocity) && velocity >= 1 && velocity <= 127
            guard pitchOk, spanOk, velOk else { throw SproutError("音符数据不合法") }
            let nid: String
            if let raw = n["id"]?.asString, jsSafeId(raw), !noteIds.contains(raw) { nid = raw } else { nid = jsUid() }
            noteIds.insert(nid)
            var note = JSONObject()
            note["id"] = .string(nid)
            note["pitch"] = .number(meta.kind == "drum" ? Double(meta.pitch ?? Int(pitch)) : pitch)
            note["start"] = .number(round4(start))
            note["duration"] = .number(round4(min(duration, bars * 4 - start)))
            note["velocity"] = .number(velocity.rounded(.toNearestOrAwayFromZero))
            if n.has("timingOffset") {
                guard let to = n["timingOffset"]?.asNumber, jsIsFinite(to), abs(to) <= 0.04 else {
                    throw SproutError("人性化偏移数据不合法")
                }
                note["timingOffset"] = .number(round4(to))
            }
            outNotes.append(note)
        }
        total += outNotes.count
        if total > Tables.shared.maxProjectNotes { throw SproutError("工程超过 12000 音符上限") }
        outNotes = stableSorted(outNotes) { a, b in
            let sa = a["start"]?.asNumber ?? 0, sb = b["start"]?.asNumber ?? 0
            if sa != sb { return sa < sb }
            return (a["pitch"]?.asNumber ?? 0) < (b["pitch"]?.asNumber ?? 0)
        }
        out["notes"] = .array(outNotes.map { .object($0) })
        outTracks.append(.object(out))
    }
    p["tracks"] = .array(outTracks)

    var result = p
    try ensureClips(&result, strict: versionNum == 2 || versionNum == 3)
    return result
}

// MARK: - .sprout-patterns(pattern-transfer.js 的导入路径)

public func validatePatternLibrary(_ input: JSONValue) throws -> [JSONValue] {
    guard let obj = input.asObject, let patterns = obj["patterns"] else {
        throw SproutError("文件不是完整 JSON，没有导入任何乐句")
    }
    return try normalizePatternArray(patterns)
}

/// 规范化的逆操作入口:直接校验 Pattern 数组(幂等复验、内部复用)。
public func normalizePatternArray(_ patterns: JSONValue) throws -> [JSONValue] {
    try normalizePatterns(patterns)
}

// MARK: - 文件读写

public func loadSprout(text: String) throws -> JSONValue {
    try parseJSON(text)
}

public func serializeProject(_ project: JSONObject) -> String {
    jsStringify(.object(project))
}

public func serializePatterns(_ patterns: [JSONValue]) -> String {
    jsStringify(.array(patterns))
}

/// 对拍调试:递归去掉所有 "id" 键(CLI mididump 用)。
public func stripIdsForDump(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let o):
        var out = JSONObject()
        for (k, v) in o.pairs where k != "id" { out[k] = stripIdsForDump(v) }
        return .object(out)
    case .array(let a):
        return .array(a.map(stripIdsForDump))
    default:
        return value
    }
}
