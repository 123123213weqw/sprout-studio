// 表演整理:对齐网格 / 力度缩放与抖动 / 微偏移清除或自然化 / 重叠修剪
// (performance.js 全量)。整组拒绝语义与报告结构一致。

import Foundation

public let performanceDefaults: [(String, JSONValue)] = [
    ("grid", .number(0)), ("strength", .number(100)), ("velocityScale", .number(100)),
    ("velocitySpread", .number(0)), ("timing", .string("keep")), ("timingAmount", .number(20)),
    ("seed", .number(271828)), ("overlap", .string("keep")),
]

private func defaultField(_ key: String) -> JSONValue {
    performanceDefaults.first { $0.0 == key }?.1 ?? .number(0)
}

public struct PerformancePresets {
    public let id: String
    public let name: String
    public let controls: JSONObject
}

public func performancePresetList() -> [PerformancePresets] {
    var list: [PerformancePresets] = []
    let definitions: [(String, String, [(String, JSONValue)])] = [
        ("tidy", "整齐一点", [("grid", .number(0.25)), ("timing", .string("clear"))]),
        ("natural", "自然一点", [("timing", .string("natural")), ("timingAmount", .number(25)), ("velocitySpread", .number(5))]),
        ("soft", "轻一点", [("velocityScale", .number(80))]),
        ("strong", "有力一点", [("velocityScale", .number(120))]),
    ]
    for (id, name, fields) in definitions {
        var controls = JSONObject()
        for (k, _) in performanceDefaults { controls[k] = defaultField(k) }
        for (k, v) in fields { controls[k] = v }
        list.append(PerformancePresets(id: id, name: name, controls: controls))
    }
    return list
}

public func normalizePerformance(_ input: JSONObject) throws -> JSONObject {
    let allowed = Set(performanceDefaults.map { $0.0 })
    for k in input.keys where !allowed.contains(k) {
        throw SproutError("演奏整理参数格式不正确")
    }
    var out = JSONObject()
    for (k, _) in performanceDefaults {
        out[k] = input[k] ?? defaultField(k)
    }
    let grid = jnum(out, "grid")
    guard [0, 0.125, 0.25, 0.5, 1].contains(grid) else { throw SproutError("不支持这个起点网格") }
    for (key, minV, maxV, label) in [("strength", 0.0, 100.0, "对齐程度"), ("velocityScale", 25.0, 200.0, "力度比例"), ("velocitySpread", 0.0, 20.0, "力度变化"), ("timingAmount", 0.0, 100.0, "时间松紧")] {
        let value = jnum(out, key)
        guard value.isFinite, value >= minV, value <= maxV else { throw SproutError("\(label)须为 \(jsNumber(minV))–\(jsNumber(maxV))") }
        out[key] = .number((value).rounded())
    }
    let timing = out["timing"]?.asString ?? "keep"
    let overlap = out["overlap"]?.asString ?? "keep"
    guard ["keep", "clear", "natural"].contains(timing), ["keep", "trim"].contains(overlap) else {
        throw SproutError("时间或重叠处理方式不正确")
    }
    let seed = jnum(out, "seed")
    guard jsIsInteger(seed), seed >= 0, seed <= 4294967295 else { throw SproutError("演奏种子须为 0–4294967295 整数") }
    return out
}

public func performanceTargets(_ project: JSONObject, trackId: String, scope: String = "selected", ids: [String] = [], clipId: String? = nil) throws -> [String] {
    let tracks = jarr(project["tracks"]).compactMap(jobj)
    guard let track = tracks.first(where: { $0["id"]?.asString == trackId }) else {
        throw SproutError("目标轨道已不存在")
    }
    guard ["selected", "clip", "track"].contains(scope) else { throw SproutError("整理范围不正确") }
    var notes: [JSONObject]
    if scope == "selected" {
        guard Set(ids).count == ids.count else { throw SproutError("音符选择格式不正确") }
        let set = Set(ids)
        notes = jarr(track["notes"]).compactMap(jobj).filter { set.contains($0["id"]?.asString ?? "") }
        guard notes.count == ids.count else { throw SproutError("所选音符已改变，请重新选择") }
    } else if scope == "clip" {
        guard let clip = jarr(track["clips"]).compactMap(jobj).first(where: { $0["id"]?.asString == clipId }) else {
            throw SproutError("先选择一个音块")
        }
        notes = notesInClip(track, clip)
    } else {
        notes = jarr(track["notes"]).compactMap(jobj)
    }
    guard !notes.isEmpty else { throw SproutError("这个范围没有音符") }
    return notes.map { $0["id"]?.asString ?? "" }
}

private func floor4(_ x: Double) -> Double {
    ((x + 1e-10) * 10000).rounded(.down) / 10000
}

/// n.toFixed(4) 的字符串(与 JS 逐字符一致;String(format:) 受区域影响,须固定 POSIX)。
func toFixed4LocaleIndependent(_ x: Double) -> String {
    String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), x)
}

public struct PerformanceReport {
    public var changed = 0
    public var velocity = 0
    public var timing = 0
    public var shortened = 0
    public var limitedTiming = 0
    public var clampedVelocity = 0
    public var overlapBefore = 0
    public var overlapAfter = 0
    public var detached = 0
    public var blocked: [String] = []
}

/// planPerformance:整组拒绝语义(blocked 非空则 project 为 nil)。
public func planPerformance(_ project: JSONObject, trackId: String, scope: String = "selected",
                            ids: [String] = [], clipId: String? = nil,
                            controls input: JSONObject) throws -> (project: JSONObject?, report: PerformanceReport) {
    let before = try validateProject(.object(project))
    let c = try normalizePerformance(input)
    let targetIds = try performanceTargets(before, trackId: trackId, scope: scope, ids: ids, clipId: clipId)
    let chosen = Set(targetIds)
    let seed = Int(jnum(c, "seed", 271828))
    let swing = jnum(before, "swing")

    var out = before
    let beforeTracks = jarr(before["tracks"]).compactMap(jobj)
    guard let original = beforeTracks.first(where: { $0["id"]?.asString == trackId }) else {
        throw SproutError("目标轨道已不存在")
    }
    let originalClips = jarr(original["clips"]).compactMap(jobj)
    var oldNotes: [String: JSONObject] = [:]
    var owners: [String: JSONObject] = [:]
    for n in jarr(original["notes"]).compactMap(jobj) {
        let id = n["id"]?.asString ?? ""
        oldNotes[id] = n
        owners[id] = clipAt(originalClips, jnum(n, "start"))
    }

    var report = PerformanceReport()
    var limitedTiming = 0
    var clampedVelocity = 0
    // key = regionId:old.start.toFixed(4)
    var groups: [String: [JSONObject]] = [:]
    var groupOrder: [String] = []

    var newNotes: [JSONObject] = []
    for nv in jarr(original["notes"]) {
        guard var n = jobj(nv) else { continue }
        guard chosen.contains(n["id"]?.asString ?? "") else { continue }
        guard let region = owners[n["id"]?.asString ?? ""] else { throw SproutError("音符没有所属音块") }
        let old = oldNotes[n["id"]?.asString ?? ""]!
        let grid = jnum(c, "grid")
        if grid != 0 {
            let aligned = (jnum(n, "start") / grid).rounded() * grid
            n["start"] = .number(round4(jnum(n, "start") + (aligned - jnum(n, "start")) * jnum(c, "strength", 100) / 100))
        }
        let regionStart = jnum(region, "start"), regionEnd = regionStart + jnum(region, "length", 4)
        let trackClipsNow = jarr(original["clips"]).compactMap(jobj)
        let newOwner = clipAt(trackClipsNow, jnum(n, "start"))
        let startOk = jnum(n, "start") >= regionStart - EPS && jnum(n, "start") + jnum(n, "duration", 0.125) <= regionEnd + EPS
        let ownerOk = newOwner?["id"]?.asString == region["id"]?.asString
        guard startOk, ownerOk else {
            throw SproutError("对齐后音符越过原音块边界；整组不会改动，请降低对齐程度或延长音块")
        }
        let raw = (jnum(n, "velocity", 100) * jnum(c, "velocityScale", 100) / 100
            + (randomAt(seed: seed, key: "velocity:\(trackId):\(n["id"]?.asString ?? "")") * 2 - 1) * jnum(c, "velocitySpread")).rounded()
        let clamped = clamp(raw, 1, 127)
        n["velocity"] = .number(clamped)
        if raw != clamped { clampedVelocity += 1 }
        let timing = c["timing"]?.asString ?? "keep"
        if timing == "clear" {
            n["timingOffset"] = nil
        } else if timing == "natural" {
            let key = "\(region["id"]?.asString ?? ""):\(toFixed4LocaleIndependent(jnum(old, "start")))"
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(n)
            continue // groups 处理后再加入
        } else {
            let to = n.has("timingOffset") ? jnum(n, "timingOffset") : 0
            let start2 = jnum(n, "start")
            let dur = jnum(n, "duration", 0.125)
            guard start2 + to >= regionStart - EPS, start2 + to + dur <= regionEnd + EPS else {
                throw SproutError("对齐后原微偏移越界；请选择清除或重新生成微偏移，整组不会改动")
            }
        }
        newNotes.append(n)
    }

    for key in groupOrder {
        guard var notes = groups[key] else { continue }
        let extent = 0.04 * jnum(c, "timingAmount", 20) / 100
        var low = -extent
        var high = extent
        for n in notes {
            guard let region = owners[n["id"]?.asString ?? ""] else { continue }
            let rs = jnum(region, "start"), re = rs + jnum(region, "length", 4)
            low = max(low, rs - jnum(n, "start"))
            high = min(high, re - jnum(n, "start") - jnum(n, "duration", 0.125))
        }
        let rawOffset = (randomAt(seed: seed, key: "time:\(trackId):\(key)") * 2 - 1) * extent
        let offset = round4(clamp(rawOffset, low, high))
        if rawOffset < low || rawOffset > high { limitedTiming += notes.count }
        for i in notes.indices {
            if offset != 0 {
                notes[i]["timingOffset"] = .number(offset)
            } else {
                notes[i]["timingOffset"] = nil
            }
            newNotes.append(notes[i])
        }
    }

    // 重叠修剪(JS:events(track) 含未选中音符,邻接按全轨事件序)
    var blocked: [String] = []
    var working: [JSONObject] = []
    let updatedById = Dictionary(uniqueKeysWithValues: newNotes.map { ($0["id"]?.asString ?? "", $0) })
    for nv in jarr(original["notes"]) {
        guard let n = jobj(nv) else { continue }
        let id = n["id"]?.asString ?? ""
        working.append(updatedById[id] ?? n)
    }
    if (c["overlap"]?.asString ?? "keep") == "trim" {
        var events: [(index: Int, start: Double, end: Double)] = []
        for (i, n) in working.enumerated() {
            let start = performanceBeat(n, swing, owners[n["id"]?.asString ?? ""])
            events.append((i, start, start + jnum(n, "duration", 0.125)))
        }
        events = stableSorted(events) { a, b in
            let pa = jnum(working[a.index], "pitch"), pb = jnum(working[b.index], "pitch")
            if pa != pb { return pa < pb }
            if a.start != b.start { return a.start < b.start }
            let sa = jnum(working[a.index], "start"), sb = jnum(working[b.index], "start")
            if sa != sb { return sa < sb }
            return (working[a.index]["id"]?.asString ?? "") < (working[b.index]["id"]?.asString ?? "")
        }
        for i in 0..<(events.count - 1) {
            let current = events[i]
            let next = events[i + 1]
            let n = working[current.index]
            guard chosen.contains(n["id"]?.asString ?? ""),
                  jnum(n, "pitch") == jnum(working[next.index], "pitch"),
                  current.end > next.start + EPS else { continue }
            guard let region = owners[n["id"]?.asString ?? ""] else { continue }
            let to = n.has("timingOffset") ? jnum(n, "timingOffset") : 0
            let onset = max(jnum(region, "start"), swungBeat(jnum(n, "start"), swing) + to)
            let available = floor4(next.start - onset)
            if available < 0.0313 {
                blocked.append("同音高同时起音或间隔太小，无法只缩短前音；请手动移开 / 删除重复音符，或保留重叠。")
                continue
            }
            working[current.index]["duration"] = .number(round4(min(jnum(n, "duration", 0.125), available)))
        }
    }

    report.overlapBefore = performanceOverlaps(original, swing, targetIds)
    // 重建轨道音符:未选中的保持原样,数值未变的逐字节保留
    var finalNotes: [JSONValue] = []
    var changedCount = 0
    for (wi, nv) in jarr(original["notes"]).enumerated() {
        guard let n = jobj(nv) else { finalNotes.append(nv); continue }
        let id = n["id"]?.asString ?? ""
        if chosen.contains(id) {
            let updated = working[wi]
            let velocityChanged = jnum(updated, "velocity") != jnum(n, "velocity")
            let startChanged = jnum(updated, "start") != jnum(n, "start")
            let durationChanged = jnum(updated, "duration") != jnum(n, "duration")
            // JS differs: (a.timingOffset||0)!==(b.timingOffset||0) —— 显式 0 与缺省等价
            let timingChanged = jnum(updated, "timingOffset") != jnum(n, "timingOffset")
            if velocityChanged || startChanged || durationChanged || timingChanged {
                changedCount += 1
                if velocityChanged { report.velocity += 1 }
                if timingChanged { report.timing += 1 }
                if durationChanged { report.shortened += 1 }
                finalNotes.append(.object(updated))
            } else {
                finalNotes.append(nv)
            }
        } else {
            finalNotes.append(nv)
        }
    }
    report.changed = changedCount
    report.limitedTiming = limitedTiming
    report.clampedVelocity = clampedVelocity

    // 结果边界校验
    for nv in finalNotes {
        guard let n = jobj(nv), chosen.contains(n["id"]?.asString ?? "") else { continue }
        guard let region = owners[n["id"]?.asString ?? ""] else { continue }
        let rs = jnum(region, "start"), re = rs + jnum(region, "length", 4)
        let to = n.has("timingOffset") ? jnum(n, "timingOffset") : 0
        let dur = jnum(n, "duration", 0.125)
        guard dur >= 0.0313 - EPS,
              jnum(n, "start") + to >= rs - EPS,
              jnum(n, "start") + to + dur <= re + EPS else {
            throw SproutError("整理结果超出音块或音符长度边界，整组不会改动")
        }
    }

    // 应用后的重叠
    var appliedTrack = original
    appliedTrack["notes"] = .array(working.map { .object($0) })
    report.overlapAfter = performanceOverlaps(appliedTrack, swing, targetIds)
    if (c["overlap"]?.asString ?? "keep") == "trim" && report.overlapAfter > 0 {
        blocked.append("仍有与选区有关的重叠：未选中的前音保持不变。请扩大整理范围或选择保留重叠。")
    }
    report.blocked = Array(Set(blocked)).sorted()

    if !report.blocked.isEmpty {
        return (nil, report)
    }

    var tracksOut: [JSONValue] = []
    for tv in jarr(out["tracks"]) {
        guard var t = jobj(tv) else { tracksOut.append(tv); continue }
        if t["id"]?.asString == trackId {
            t["notes"] = .array(finalNotes)
        }
        tracksOut.append(.object(t))
    }
    out["tracks"] = .array(tracksOut)
    try ensureClips(&out, strict: false)
    let result = try validateProject(.object(out))
    let resultTracks = jarr(result["tracks"]).compactMap(jobj)
    guard let newTrack = resultTracks.first(where: { $0["id"]?.asString == trackId }) else {
        throw SproutError("目标轨道已不存在")
    }
    // 校验器不得改动选中音符
    let resultById = Dictionary(uniqueKeysWithValues: jarr(newTrack["notes"]).compactMap(jobj).map { ($0["id"]?.asString ?? "", $0) })
    for nv in finalNotes {
        guard let planned = jobj(nv), chosen.contains(planned["id"]?.asString ?? "") else { continue }
        let actual = resultById[planned["id"]?.asString ?? ""]
        guard let actual = actual else { throw SproutError("整理结果校验改变了音符，整组没有应用") }
        let differ = jnum(actual, "start") != jnum(planned, "start")
            || jnum(actual, "duration") != jnum(planned, "duration")
            || jnum(actual, "velocity") != jnum(planned, "velocity")
            || jnum(actual, "timingOffset") != jnum(planned, "timingOffset")
        if differ { throw SproutError("整理结果校验改变了音符，整组没有应用") }
    }
    let newClips = jarr(newTrack["clips"]).compactMap(jobj)
    report.detached = jarr(original["clips"]).compactMap(jobj).filter { oldClip in
        guard oldClip.has("patternId") else { return false }
        let match = newClips.first { $0["id"]?.asString == oldClip["id"]?.asString }
        return !(match?.has("patternId") ?? false)
    }.count
    report.overlapAfter = performanceOverlaps(newTrack, swing, targetIds)
    return (result, report)
}
