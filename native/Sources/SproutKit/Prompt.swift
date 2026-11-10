// 离线灵感引擎的文字入口:generateFromPrompt(music.js)。
// 关键词规则引擎(风格/范围/长度/速度/调性识别 + 目标轨道重写),确定性可对拍。

import Foundation

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

/// 返回第一个捕获组(与 JS match()[1] 对应)。
private func firstCapture(_ text: String, _ pattern: String, caseInsensitive: Bool = false) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var options: NSRegularExpression.MatchingOptions = []
    _ = caseInsensitive
    guard let m = regex.firstMatch(in: text, options: options, range: range),
          m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r])
}

public struct PromptResult {
    public let project: JSONObject
    public let summary: String
    public let seed: Double
}

public func generateFromPrompt(
    _ project: JSONObject,
    _ prompt: String,
    scope: String = "all",
    selectedTrackId: String? = nil,
    controls: JSONObject? = nil,
    forcedSeed: Double? = nil
) throws -> PromptResult {
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw SproutError("先写下你想要的感觉") }
    guard ["all", "selected", "drums", "section"].contains(scope) else { throw SproutError("修改范围不正确") }

    var p = project
    try ensureClips(&p, strict: false)
    var parameters: JSONObject? = nil
    if let controls = controls {
        parameters = try normalizeControls(.object(controls), seed: jnum(p, "seed", 1))
    }
    var style = p["style"]?.asString ?? "lofi"
    if matches(text, "house|舞曲|四四拍|跳舞") { style = "house" }
    else if matches(text, "hip.?hop|嘻哈|说唱|boom.?bap") { style = "hiphop" }
    else if matches(text, "ambient|氛围|空灵|冥想") { style = "ambient" }
    else if matches(text, "lo.?fi|雨夜|松弛") { style = "lofi" }

    var targets: [JSONObject]
    if scope == "selected" {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }.filter { $0["id"]?.asString == selectedTrackId }
    } else if scope == "drums" || matches(text, "只.*(?:鼓|节奏)") {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }.filter { $0["kind"]?.asString == "drum" }
    } else if matches(text, "只.*贝斯") {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }.filter { $0["instrument"]?.asString == "bass" }
    } else if matches(text, "只.*(?:旋律|主旋律)") {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }.filter { $0["instrument"]?.asString == "lead" }
    } else if matches(text, "只.*(?:钢琴|和弦)") {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }.filter { ["keys", "pad"].contains($0["instrument"]?.asString ?? "") }
    } else {
        targets = jarr(p["tracks"]).compactMap { $0.asObject }
    }
    guard !targets.isEmpty else { throw SproutError("这个范围没有可编曲的轨道，请先添加对应乐器") }

    let narrow = scope != "all" || targets.count != jarr(p["tracks"]).count
    let ids = Set(targets.map { $0["id"]?.asString ?? "" })

    var bars = jnum(p, "bars", 8)
    if !narrow, let m = firstCapture(text, "(?:做|生成|改成|长度|扩展)?\\s*(4|8|16|32|64)\\s*小节") {
        bars = Double(m) ?? bars
    }
    var bpm = jnum(p, "bpm", 90)
    if !narrow {
        if let m = firstCapture(text, "(\\d{2,3})\\s*(?:bpm|拍每分钟)", caseInsensitive: true) {
            bpm = clamp(Double(m) ?? bpm, 40, 200)
        } else if style != p["style"]?.asString {
            bpm = Tables.shared.styles.first(where: { $0.id == style })?.bpm ?? bpm
        }
        if matches(text, "慢一点|更慢|放慢") { bpm = clamp(bpm - 8, 40, 200) }
        if matches(text, "快一点|更快|加快") { bpm = clamp(bpm + 8, 40, 200) }
    }

    var key = p["key"]?.asString ?? "A minor"
    if !narrow {
        for candidate in Tables.shared.keys.keys.sorted() {
            let parts = candidate.split(separator: " ").map(String.init)
            let pattern = parts[0] + "\\s*(?:" + (parts[1] == "minor" ? "minor|小调" : "major|大调") + ")"
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                key = candidate
            }
        }
    }

    var seed: Double
    if let s = parameters?["seed"]?.asNumber {
        seed = s
    } else if let forced = forcedSeed {
        seed = forced
    } else {
        seed = Double((Int(jnum(p, "seed", 1)) + Int.random(in: 1...100_000)) & 0xffffffff)
    }

    let base = try generateProject(GenerateOptions(
        style: style, key: key, bars: bars, seed: Int(seed), bpm: bpm,
        name: p["name"]?.asString, composition: parameters
    ))
    // JS:bars 变化时 out = resizeProject(p, bars)(repeat 铺满),否则原样
    var out = bars == jnum(p, "bars", 8) ? p : try resizeProject(p, toBars: bars, fill: "repeat")
    if !narrow {
        out["bpm"] = .number(bpm)
        out["key"] = .string(key)
        out["style"] = .string(style)
        out["swing"] = .number(matches(text, "律动|摇摆") ? 24 : jnum(base, "swing", 12))
        out["seed"] = .number(seed)
        if let parameters = parameters {
            out["composition"] = .object(parameters)
        } else {
            out["composition"] = nil
        }
    }

    let baseTracks = jarr(base["tracks"]).compactMap { $0.asObject }
    var outTracks: [JSONValue] = []
    for tv in jarr(out["tracks"]) {
        guard var t = tv.asObject else { outTracks.append(tv); continue }
        guard ids.contains(t["id"]?.asString ?? "") else { outTracks.append(tv); continue }
        let instrument = t["instrument"]?.asString ?? "lead"
        let fallbackMap = ["pluck": "lead", "pad": "keys", "keys": "pad"]
        let src = baseTracks.first { $0["instrument"]?.asString == instrument }
            ?? baseTracks.first { $0["instrument"]?.asString == (fallbackMap[instrument] ?? instrument) }
        guard let source = src else { throw SproutError("没有这个乐器的离线编曲模板") }

        var newNotes: [JSONValue] = []
        let clips = jarr(t["clips"]).compactMap { $0.asObject }
        for nv in jarr(source["notes"]) {
            guard let n = nv.asObject else { continue }
            let start = jnum(n, "start")
            guard let c = clipAt(clips, start) else { continue }
            var copy = n
            copy["id"] = .string(jsUid())
            let regionEnd = jnum(c, "start") + jnum(c, "length", 4)
            copy["duration"] = .number(round4(min(jnum(n, "duration"), regionEnd - start)))
            if jnum(copy, "duration") >= 0.03125 {
                newNotes.append(.object(copy))
            }
        }

        var notes: [JSONObject] = newNotes.compactMap { $0.asObject }
        if parameters == nil && matches(text, "温柔|柔和|安静|少一点|不要太满|稀疏") {
            notes = notes.enumerated().compactMap { index, n in
                let instrumentName = instrument
                if instrumentName == "hat", index % 2 != 0 { return nil }
                if instrumentName == "lead", index % 3 == 2 { return nil }
                var copy = n
                copy["velocity"] = .number(clamp((jnum(n, "velocity") * 0.8).rounded(), 15, 110))
                return copy
            }
        }
        if parameters == nil && matches(text, "有力|强烈|能量|厚实") {
            notes = notes.map { n in
                var copy = n
                copy["velocity"] = .number(clamp(jnum(n, "velocity") + 14, 1, 127))
                return copy
            }
        }
        if matches(text, "半拍"), instrument == "snare" {
            notes = []
            for b in 0..<Int(jnum(out, "bars", 8)) {
                if clipAt(clips, Double(b * 4 + 2)) != nil {
                    var n = JSONObject()
                    n["id"] = .string(jsUid())
                    n["pitch"] = .number(38)
                    n["start"] = .number(Double(b * 4 + 2))
                    n["duration"] = .number(0.13)
                    n["velocity"] = .number(95)
                    notes.append(n)
                }
            }
        }
        if matches(text, "更多|丰富|更有变化"), instrument == "bass" {
            notes = notes.enumerated().map { index, n in
                var copy = n
                if index % 3 == 1 { copy["pitch"] = .number(jnum(n, "pitch") + 12) }
                return copy
            }
        }
        if matches(text, "明亮|开心"), ["lead", "pluck"].contains(instrument) {
            notes = notes.map { n in
                var copy = n
                copy["pitch"] = .number(clamp(jnum(n, "pitch") + 12, 24, 108))
                return copy
            }
        }
        t["notes"] = .array(notes.map { .object($0) })
        outTracks.append(.object(t))
    }
    out["tracks"] = .array(outTracks)

    let names = targets.map { $0["name"]?.asString ?? "" }.joined(separator: "、")
    let styleName = Tables.shared.styles.first(where: { $0.id == style })?.name ?? style
    let summary = narrow
        ? "仅更新\(names)，保持其他轨道、音块布局与全局设置。"
        : "重新编写 \(styleName) 音符，保留原有乐器、音块布局与混音。"
    let fullSummary = summary + "\(Int(bpm)) BPM · \(Int(bars)) 小节。"
    try ensureClips(&out, strict: false)
    return PromptResult(project: try validateProject(.object(out)), summary: fullSummary, seed: seed)
}
