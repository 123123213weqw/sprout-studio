// Pattern 批量编排与实例管理(pattern-arrange.js 全量)+
// 音色收藏(sound-bank.js)+ 模型回执(model-receipt.js)。

import Foundation

// MARK: - planPatternSeries(整组显式放置,不覆盖不部分)

public let patternBatchMax = 32
public let patternInstanceMax = 4096

private func totalNotes(_ p: JSONObject) -> Int {
    jarr(p["tracks"]).reduce(0) { $0 + jarr(jobj($1)?["notes"]).count }
}

public func planPatternSeries(_ project: JSONObject, patternId: String, trackId: String,
                              start startIn: Double, count: Int = 1, interval: Double? = nil,
                              linked: Bool = true, extend: Bool = false) throws -> (project: JSONObject, clipIds: [String], extended: Bool) {
    let before = try validateProject(.object(project))
    guard let source = jarr(before["patterns"]).compactMap(jobj).first(where: { $0["id"]?.asString == patternId }) else {
        throw SproutError("源乐句已不存在，请重新打开 Pattern 库")
    }
    let tracks = jarr(before["tracks"]).compactMap(jobj)
    guard let old = tracks.first(where: { $0["id"]?.asString == trackId }) else {
        throw SproutError("乐句与轨道不兼容；鼓只可放到同种鼓轨")
    }
    let sourceKind = source["kind"]?.asString ?? "tonal"
    let oldKind = old["kind"]?.asString ?? "tonal"
    guard sourceKind == oldKind, sourceKind != "drum" || source["instrument"]?.asString == old["instrument"]?.asString else {
        throw SproutError("乐句与轨道不兼容；鼓只可放到同种鼓轨")
    }
    guard startIn.isFinite, startIn >= 0, count >= 1, count <= patternBatchMax else {
        throw SproutError("起点、份数或关联方式不正确；一次可放 1–32 份")
    }
    let sourceLength = jnum(source, "length", 4)
    var theInterval = interval ?? sourceLength
    guard theInterval.isFinite, theInterval >= 0.25, theInterval <= 256 else {
        throw SproutError("间隔须为 0.25–256 拍")
    }
    let start = round4(startIn)
    theInterval = round4(theInterval)
    if count > 1 && theInterval < sourceLength - EPS {
        throw SproutError("间隔短于乐句长度，会让新音块互相重叠")
    }
    struct Row { let index: Int; let start: Double }
    var rows: [Row] = []
    for i in 0..<count { rows.append(Row(index: i + 1, start: round4(start + Double(i) * theInterval))) }
    let end = round4(rows[rows.count - 1].start + sourceLength)
    if end > jnum(before, "bars", 4) * 4 + EPS && !extend {
        throw SproutError("放置超出工程，请明确勾选空白延长")
    }
    let bars = end > jnum(before, "bars", 4) * 4 + EPS ? try expandedBars(end, current: jnum(before, "bars", 4)) : jnum(before, "bars", 4)
    for (i, r) in rows.enumerated() {
        if i > 0 && r.start < rows[i - 1].start + sourceLength - EPS {
            throw SproutError("舍入后新音块互相重叠")
        }
        for c in jarr(old["clips"]).compactMap(jobj) {
            let cs = jnum(c, "start"), cl = jnum(c, "length", 4)
            if r.start < cs + cl - EPS && r.start + sourceLength > cs + EPS {
                throw SproutError("第 \(r.index) 份的第 \(jsNumber(round4(r.start / 4 + 1))) 小节已有音块，整组没有放置")
            }
        }
    }
    let sourceNotes = jarr(source["notes"]).compactMap(jobj)
    let addedNotes = count * sourceNotes.count
    guard jarr(old["clips"]).count + count <= 256,
          jarr(old["notes"]).count + addedNotes <= 4000,
          totalNotes(before) + addedNotes <= Tables.shared.maxProjectNotes else {
        throw SproutError("超过音块 / 每轨 4000 / 全工程 12000 音符上限")
    }

    var p = before
    p["bars"] = .number(bars)
    var used = Set<String>()
    if let pid = p["id"]?.asString { used.insert(pid) }
    for sv in jarr(p["sections"]) { if let id = jobj(sv)?["id"]?.asString { used.insert(id) } }
    for sv in jarr(p["patterns"]) {
        guard let s = jobj(sv), let id = s["id"]?.asString else { continue }
        used.insert(id)
        for nv in jarr(s["notes"]) { if let id2 = jobj(nv)?["id"]?.asString { used.insert(id2) } }
    }
    for tv in jarr(p["tracks"]) {
        guard let t = jobj(tv) else { continue }
        if let id = t["id"]?.asString { used.insert(id) }
        for cv in jarr(t["clips"]) { if let id = jobj(cv)?["id"]?.asString { used.insert(id) } }
        for nv in jarr(t["notes"]) { if let id = jobj(nv)?["id"]?.asString { used.insert(id) } }
    }

    var clipIds: [String] = []
    var tracksOut: [JSONValue] = []
    for tv in jarr(p["tracks"]) {
        guard var target = jobj(tv) else { tracksOut.append(tv); continue }
        if target["id"]?.asString == trackId {
            var clips = jarr(target["clips"])
            var notes = jarr(target["notes"])
            for row in rows {
                let clipId = jsUid()
                used.insert(clipId)
                var clip = JSONObject()
                clip["id"] = .string(clipId)
                clip["name"] = .string(jsSlice16(source["name"]?.asString ?? "乐句", 40))
                clip["start"] = .number(row.start)
                clip["length"] = .number(sourceLength)
                clip["muted"] = .bool(false)
                if linked { clip["patternId"] = .string(patternId) }
                if linked {
                    let materialized = materializedNotes(pattern: source, clip: clip)
                    for n in materialized {
                        let nid = n["id"]?.asString ?? ""
                        if used.contains(nid) { throw SproutError("共享音符标识碰撞，没有放置任何内容") }
                        used.insert(nid)
                        notes.append(.object(n))
                    }
                } else {
                    for n in sourceNotes {
                        let nid = jsUid()
                        used.insert(nid)
                        var copy = n
                        copy["id"] = .string(nid)
                        copy["start"] = .number(round4(row.start + jnum(n, "start")))
                        notes.append(.object(copy))
                    }
                }
                clips.append(.object(clip))
                clipIds.append(clipId)
            }
            target["clips"] = .array(clips)
            target["notes"] = .array(notes)
        }
        tracksOut.append(.object(target))
    }
    p["tracks"] = .array(tracksOut)
    try ensureClips(&p, strict: false)
    let next = try validateProject(.object(p))
    if serializeProject(next).utf8.count > 3_000_000 {
        throw SproutError("操作后工程超过 3 MB 保存上限，请减少所选数量")
    }
    return (next, clipIds, bars != jnum(before, "bars", 4))
}

// MARK: - planPatternInstances(静音/取消静音/独立化/删除所选实例)

public func planPatternInstances(_ project: JSONObject, patternId: String, clipIds: [String], action: String) throws -> JSONObject {
    let before = try validateProject(.object(project))
    guard jarr(before["patterns"]).compactMap(jobj).contains(where: { $0["id"]?.asString == patternId }) else {
        throw SproutError("源乐句已不存在，请重新打开 Pattern 库")
    }
    guard ["mute", "unmute", "detach", "delete"].contains(action) else {
        throw SproutError("请选择静音、取消块静音、独立化或删除所选块")
    }
    let refs = patternInstances(before, patternId: patternId)
    let refClipIds = Set(refs.map(\.clipId))
    guard !clipIds.isEmpty, clipIds.count <= patternInstanceMax,
          Set(clipIds).count == clipIds.count,
          clipIds.allSatisfy({ refClipIds.contains($0) }) else {
        throw SproutError("请至少选择一个仍关联此源的音块，不能重复或包含独立副本")
    }
    let selected = Set(clipIds)
    var p = before
    var tracksOut: [JSONValue] = []
    for tv in jarr(p["tracks"]) {
        guard var t = jobj(tv) else { tracksOut.append(tv); continue }
        let clipsHere = jarr(t["clips"]).compactMap(jobj).filter { selected.contains($0["id"]?.asString ?? "") }
        if clipsHere.isEmpty { tracksOut.append(tv); continue }
        var removedNoteIds = Set<String>()
        var clipsNew: [JSONValue] = []
        for cv in jarr(t["clips"]) {
            guard var c = jobj(cv) else { clipsNew.append(cv); continue }
            guard selected.contains(c["id"]?.asString ?? "") else { clipsNew.append(cv); continue }
            if action == "delete" {
                for n in notesInClip(t, c) { removedNoteIds.insert(n["id"]?.asString ?? "") }
                continue // 不保留
            }
            if action == "detach" { c["patternId"] = nil }
            if action == "mute" { c["muted"] = .bool(true) }
            if action == "unmute" { c["muted"] = .bool(false) }
            clipsNew.append(.object(c))
        }
        t["clips"] = .array(clipsNew)
        if action == "delete" {
            t["notes"] = .array(jarr(t["notes"]).filter { nv in
                guard let n = jobj(nv) else { return true }
                return !removedNoteIds.contains(n["id"]?.asString ?? "")
            })
        }
        tracksOut.append(.object(t))
    }
    p["tracks"] = .array(tracksOut)
    try ensureClips(&p, strict: false)
    let next = try validateProject(.object(p))
    if serializeProject(next).utf8.count > 3_000_000 {
        throw SproutError("操作后工程超过 3 MB 保存上限，请减少所选数量")
    }
    return next
}

// MARK: - 音色收藏(sound-bank.js)

public let soundBankLimits = (entries: 32, bytes: 262_144)

public struct SoundCollectionEntry {
    public var id: String
    public var name: String
    public var instrument: String
    public var sound: JSONObject? // nil = 原始音色
    public var createdAt: Double
    public var archived: Bool
    public init(name: String, instrument: String, sound: JSONObject?) {
        self.id = jsUid()
        self.name = name
        self.instrument = instrument
        self.sound = sound
        self.createdAt = Date().timeIntervalSince1970
        self.archived = false
    }
}

public func normalizeSoundCollection(_ input: JSONObject) throws -> JSONObject {
    let required = ["id", "name", "instrument", "sound", "createdAt", "archived"]
    for k in input.keys where !required.contains(k) { throw SproutError("音色收藏字段不完整或包含未知字段") }
    for k in required where !input.has(k) { throw SproutError("音色收藏字段不完整或包含未知字段") }
    guard let id = input["id"]?.asString,
          id.range(of: "^[a-zA-Z0-9-]{1,80}$", options: .regularExpression) != nil,
          let createdAt = input["createdAt"]?.asNumber, jsIsInteger(createdAt), createdAt >= 0,
          let archived = input["archived"]?.asBool else {
        throw SproutError("音色收藏标识或时间不正确")
    }
    guard let instrument = input["instrument"]?.asString,
          Tables.shared.instruments[instrument] != nil else { throw SproutError("收藏音源不支持") }
    guard let nameRaw = input["name"]?.asString,
          !nameRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          nameRaw.count <= 60 else { throw SproutError("音色名称须为 1–60 个字符") }
    var sound: JSONValue = .null
    if case .null = input["sound"] ?? .null {
        sound = .null
    } else if let s = input["sound"]?.asObject {
        let defaults = Tables.shared.soundDefaults[instrument] ?? JSONObject()
        for k in s.keys where !defaults.has(k) { throw SproutError("音色收藏字段不完整或包含未知字段") }
        let normalized = try normalizeSound(instrument, .object(s))
        for (k, dv) in normalized.pairs {
            let raw = s[k]?.asNumber
            let norm = dv.asNumber
            if let r = raw, let n = norm {
                // 有效值判定:输入须等于规范化结果(四位小数内)
                if abs(r - n) > 0.0001 { throw SproutError("音色参数须使用最多四位小数的有效值") }
            }
        }
        sound = .object(normalized)
    } else {
        throw SproutError("音色收藏字段不完整或包含未知字段")
    }
    var out = JSONObject()
    out["id"] = .string(id)
    out["name"] = .string(nameRaw.trimmingCharacters(in: .whitespacesAndNewlines))
    out["instrument"] = .string(instrument)
    out["sound"] = sound
    out["createdAt"] = .number(createdAt)
    out["archived"] = .bool(archived)
    return out
}

public func soundCompatible(_ source: String, _ target: String) -> Bool {
    guard let s = Tables.shared.instruments[source], let t = Tables.shared.instruments[target] else { return false }
    return source == target || (s.kind == "tonal" && t.kind == "tonal")
}

/// 收藏应用到目标轨道:返回 nil 表示"使用原始音色"(清除自定义)。
public func collectionForTrack(_ input: JSONObject, target: String) throws -> JSONObject? {
    let entry = try normalizeSoundCollection(input)
    if entry["archived"]?.asBool == true { throw SproutError("请先恢复归档的音色") }
    let instrument = entry["instrument"]?.asString ?? ""
    guard soundCompatible(instrument, target) else {
        throw SproutError("鼓收藏仅适用于同种鼓；旋律收藏不能用于鼓")
    }
    if case .null = entry["sound"] ?? .null {
        if instrument != target {
            throw SproutError("原始音色只适用于原音源；不能把另一音源的原始合成复制过来")
        }
        return nil
    }
    return entry["sound"]?.asObject
}

public func exportSoundFile(_ entries: [JSONObject]) throws -> String {
    guard !entries.isEmpty, entries.count <= soundBankLimits.entries else {
        throw SproutError("请选择 1–32 个音色导出")
    }
    var presets: [JSONValue] = []
    for e in entries {
        let p = try normalizeSoundCollection(e)
        var preset = JSONObject()
        preset["name"] = p["name"]!
        preset["instrument"] = p["instrument"]!
        preset["sound"] = p["sound"] ?? .null
        presets.append(.object(preset))
    }
    var file = JSONObject()
    file["format"] = .string("sprout-sounds")
    file["version"] = .number(1)
    file["presets"] = .array(presets)
    let out = jsStringify(.object(file))
    if out.utf8.count > soundBankLimits.bytes { throw SproutError("音色文件超过 256 KiB") }
    return out
}

public func parseSoundFile(_ text: String) throws -> [JSONObject] {
    guard text.utf8.count <= soundBankLimits.bytes else { throw SproutError("音色文件须为不超过 256 KiB 的文本") }
    guard let value = try? parseJSON(text), let file = value.asObject else { throw SproutError("音色文件不是有效 JSON") }
    let required = ["format", "version", "presets"]
    for k in file.keys where !required.contains(k) { throw SproutError("音色收藏字段不完整或包含未知字段") }
    guard file["format"]?.asString == "sprout-sounds", jnum(file, "version") == 1,
          let presets = file["presets"]?.asArray, !presets.isEmpty,
          presets.count <= soundBankLimits.entries else {
        throw SproutError("音色文件格式 / 版本 / 数量不支持")
    }
    var out: [JSONObject] = []
    for pv in presets {
        guard let p = pv.asObject else { throw SproutError("音色收藏字段不完整或包含未知字段") }
        for k in p.keys where !["name", "instrument", "sound"].contains(k) {
            throw SproutError("音色收藏字段不完整或包含未知字段")
        }
        for k in ["name", "instrument", "sound"] where !p.has(k) {
            throw SproutError("音色收藏字段不完整或包含未知字段")
        }
        var entry = JSONObject()
        entry["id"] = .string(jsUid())
        entry["name"] = p["name"]!
        entry["instrument"] = p["instrument"]!
        entry["sound"] = p["sound"] ?? .null
        entry["createdAt"] = .number(Date().timeIntervalSince1970)
        entry["archived"] = .bool(false)
        out.append(try normalizeSoundCollection(entry))
    }
    return out
}

// MARK: - 模型回执(model-receipt.js)

public func normalizeModelReceipt(_ value: JSONValue?) -> JSONObject? {
    guard let v = value?.asObject,
          let provider = v["provider"]?.asString,
          provider == "deepseek" || provider == "compatible" else { return nil }
    func label(_ s: String?) -> String? {
        guard let s = s, s.range(of: "^[a-zA-Z0-9._:-]{1,120}$", options: .regularExpression) != nil else { return nil }
        return s
    }
    guard let model = label(v["model"]?.asString),
          let elapsed = v["elapsedMs"]?.asNumber, jsIsInteger(elapsed), elapsed >= 0, elapsed <= 120000 else { return nil }
    var usage = JSONObject()
    for key in ["prompt_tokens", "completion_tokens", "total_tokens"] {
        if let n = v["usage"]?.asObject?[key]?.asNumber, jsIsInteger(n), n >= 0, n <= 10_000_000 {
            usage[key] = .number(n)
        }
    }
    var out = JSONObject()
    out["provider"] = .string(provider)
    out["model"] = .string(model)
    out["elapsedMs"] = .number(elapsed)
    out["usage"] = .object(usage)
    out["format"] = .string(v["format"]?.asString == "sprout-score-v1" ? "sprout-score-v1" : "project")
    out["verified"] = .string("validated-notes")
    out["quality"] = .string("not-rated")
    if let requestId = label(v["requestId"]?.asString) {
        out["requestId"] = .string(requestId)
    }
    if let maxTokens = v["maxOutputTokens"]?.asNumber, jsIsInteger(maxTokens), maxTokens >= 1024, maxTokens <= 32768 {
        out["maxOutputTokens"] = .number(maxTokens)
    }
    return out
}
