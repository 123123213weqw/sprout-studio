// 离线灵感引擎:generateProject 与其依赖(composition.js 全族 + music.js 主循环)。
// 纯确定性(rng/randomAt 均 FNV/LCG 移植),与 JS 逐字节对拍。

import Foundation

// MARK: - rng / randomAt(与 JS 逐位一致)

public func rng(_ seedIn: Int) -> () -> Double {
    var a = UInt32(truncatingIfNeeded: seedIn)
    return {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

public func randomAt(seed: Int, key: String) -> Double {
    var h = UInt32(truncatingIfNeeded: seed) ^ 0x811c9dc5
    for u in key.utf16 {
        h ^= UInt32(u)
        h = h &* 0x01000193
    }
    h ^= h >> 16
    h = h &* 0x7feb352d
    h ^= h >> 15
    h = h &* 0x846ca68b
    h ^= h >> 16
    return Double(h) / 4294967296
}

// MARK: - progressionFor / voiceLead(composition.js)

public func progressionFor(mode: String, name: String = "warm") -> [Int] {
    if name == "home" { return [0, 3, 4, 0] }
    if name == "lift" { return mode == "minor" ? [0, 3, 5, 4] : [0, 5, 3, 4] }
    return mode == "minor" ? [0, 5, 2, 6] : [0, 4, 5, 3]
}

public func voiceLead(_ pitches: [Double], previous: [Double]?) -> [Double] {
    let base = pitches.sorted()
    guard let previous = previous, !previous.isEmpty else { return base }
    var best = base
    var score = Double.infinity
    for inversion in 0..<base.count {
        var rotated: [Double] = Array(base[inversion...])
        rotated += base[0..<inversion].map { $0 + 12 }
        for shift in [-24.0, -12.0, 0.0, 12.0] {
            let candidate = rotated.map { $0 + shift }
            if candidate.contains(where: { $0 < 42 || $0 > 84 }) { continue }
            var distance = 0.0
            for (i, p) in candidate.enumerated() {
                distance += abs(p - previous[min(i, previous.count - 1)])
            }
            distance += Double(abs(candidate.count - previous.count)) * 12
            if distance < score {
                best = candidate
                score = distance
            }
        }
    }
    return best
}

// MARK: - applyPerformance(composition.js)

public func applyPerformance(_ project: inout JSONObject, controls: JSONObject, density: Bool = false) throws {
    let c = try normalizeControls(.object(controls), seed: 271828)
    let seed = Int(jnum(c, "seed", 271828))
    let bars = jnum(project, "bars", 4)
    var tracks = (project["tracks"]?.asArray ?? []).compactMap(\.asObject)
    for ti in tracks.indices {
        let instrument = tracks[ti]["instrument"]?.asString ?? ""
        let clips = (tracks[ti]["clips"]?.asArray ?? []).compactMap(\.asObject)
        let sorted = stableSorted((tracks[ti]["notes"]?.asArray ?? []).compactMap(\.asObject)) { a, b in
            let sa = jnum(a, "start"), sb = jnum(b, "start")
            if sa != sb { return sa < sb }
            return jnum(a, "pitch") < jnum(b, "pitch")
        }
        // 按起点分组(key = toFixed(4) 字符串,与 JS 一致)
        var groups: [(key: String, notes: [JSONObject])] = []
        var index: [String: Int] = [:]
        for n in sorted {
            // JS 分组键是 n.start.toFixed(4) 的定宽字符串(如 "0.0000"),必须逐字符一致
            let key = String(format: "%.4f", jnum(n, "start"))
            if let i = index[key] {
                groups[i].notes.append(n)
            } else {
                index[key] = groups.count
                groups.append((key, [n]))
            }
        }
        var firstByBar: [Int: String] = [:]
        for group in groups {
            let bar = Int(floor(jnum(group.notes[0], "start") / 4))
            if firstByBar[bar] == nil { firstByBar[bar] = group.key }
        }
        var removedIds = Set<String>()
        let humanize = jnum(c, "humanize", 15)
        let energy = jnum(c, "energy", 50)
        let densityValue = jnum(c, "density", 50)
        for group in groups {
            let label = "\(instrument):\(group.key)"
            let anchor = firstByBar[Int(floor(jnum(group.notes[0], "start") / 4))] == group.key
            if density && !anchor && randomAt(seed: seed, key: "density:\(label)") > 0.05 + 0.0095 * densityValue {
                group.notes.forEach { removedIds.insert($0["id"]?.asString ?? "") }
                continue
            }
            var low = -0.04 * humanize / 100
            var high = 0.04 * humanize / 100
            for n in group.notes {
                let region = clipAt(clips, jnum(n, "start"))
                let start = max(jnum(region ?? JSONObject(), "start"), 0)
                let regionEnd = region != nil ? jnum(region!, "start") + jnum(region!, "length") : bars * 4
                low = max(low, start - jnum(n, "start"))
                high = min(high, regionEnd - jnum(n, "start") - jnum(n, "duration"))
            }
            let offset = round4(clamp((randomAt(seed: seed, key: "time:\(label)") * 2 - 1) * 0.04 * humanize / 100, low, high))
            var updated: [JSONValue] = []
            for nv in tracks[ti]["notes"]?.asArray ?? [] {
                guard var n = nv.asObject else { updated.append(nv); continue }
                guard group.notes.contains(where: { $0["id"]?.asString == n["id"]?.asString }) else {
                    updated.append(nv)
                    continue
                }
                let pitch = Int(jnum(n, "pitch"))
                let velocity = jnum(n, "velocity")
                let jitter = (randomAt(seed: seed, key: "velocity:\(label):\(pitch)") * 2 - 1) * 7 * humanize / 100
                let scaled = velocity * (0.7 + 0.006 * energy) + jitter
                n["velocity"] = .number(clamp((scaled).rounded(.toNearestOrAwayFromZero), 1, 127))
                if humanize != 0 {
                    n["timingOffset"] = .number(offset)
                } else {
                    n["timingOffset"] = nil
                }
                updated.append(.object(n))
            }
            tracks[ti]["notes"] = .array(updated)
        }
        tracks[ti]["notes"] = .array((tracks[ti]["notes"]?.asArray ?? []).filter { nv in
            guard let id = nv.asObject?["id"]?.asString else { return true }
            return !removedIds.contains(id)
        })
    }
    project["tracks"] = .array(tracks.map { .object($0) })
}

// MARK: - generateProject(music.js)

public func scalePitch(key: String, degree: Int, octave: Int = 0) -> Double {
    guard let k = Tables.shared.keys[key] else { return 60 }
    let q = Int(floor(Double(degree) / 7))
    let idx = ((degree % 7) + 7) % 7
    let mapped: Int = Int(k.root) + Int(k.scale[idx]) + (q + octave) * 12
    return Double(mapped)
}

public struct GenerateOptions {
    public var style: String
    public var key: String
    public var bars: Double
    public var seed: Int
    public var bpm: Double?
    public var name: String?
    public var composition: JSONObject?
    public init(style: String = "lofi", key: String = "A minor", bars: Double = 8, seed: Int = 271828, bpm: Double? = nil, name: String? = nil, composition: JSONObject? = nil) {
        self.style = style
        self.key = key
        self.bars = bars
        self.seed = seed
        self.bpm = bpm
        self.name = name
        self.composition = composition
    }
}

public func generateProject(_ options: GenerateOptions) throws -> JSONObject {
    var style = options.style
    let styleList = (try? styleTable()) ?? []
    if !styleList.contains(style) { style = "lofi" }
    var key = options.key
    if Tables.shared.keys[key] == nil { key = "A minor" }
    var bars = options.bars
    if !validBars(bars) { bars = 8 }
    var seed = options.seed
    var controls: JSONObject? = nil
    if let composition = options.composition {
        controls = try normalizeControls(.object(composition), seed: Double(seed))
        if let s = controls?["seed"]?.asNumber {
            seed = Int(s)
        }
    }
    let complexity = controls.map { jnum($0, "complexity", 35) }
    let random = rng(seed)

    let styleSpecs: [(id: String, bpm: Double)] = styleTableSpecs()
    let specBpm = styleSpecs.first(where: { $0.id == style })?.bpm ?? 86

    func makeTrack(_ instrument: String) -> JSONObject {
        let meta = Tables.shared.instruments[instrument]!
        var t = JSONObject()
        t["id"] = .string(jsUid())
        t["instrument"] = .string(instrument)
        t["name"] = .string(meta.name)
        t["kind"] = .string(meta.kind)
        t["color"] = .string(meta.color)
        t["volume"] = .number(instrument == "keys" ? 0.62 : instrument == "hat" ? 0.45 : 0.72)
        t["pan"] = .number(instrument == "hat" ? 0.18 : instrument == "lead" ? 0.12 : 0)
        t["muted"] = .bool(false)
        t["solo"] = .bool(false)
        t["notes"] = .array([])
        return t
    }

    func add(_ track: inout JSONObject, pitch: Double, start: Double, duration: Double, velocity: Double) {
        var note = JSONObject()
        note["id"] = .string(jsUid())
        note["pitch"] = .number(clamp(pitch, 24, 108))
        note["start"] = .number(round4(start))
        note["duration"] = .number(round4(duration))
        note["velocity"] = .number(clamp((velocity).rounded(.toNearestOrAwayFromZero), 1, 127))
        var notes = track["notes"]?.asArray ?? []
        notes.append(.object(note))
        track["notes"] = .array(notes)
    }

    let trackOrder = ["kick", "snare", "hat", "bass", style == "ambient" ? "pad" : "keys", "lead"]
    var tracks = trackOrder.map { makeTrack($0) }
    let kick = 0, snare = 1, hat = 2, bass = 3, chords = 4, lead = 5

    let keyInfo = Tables.shared.keys[key]!
    let minor = keyInfo.mode == "minor"
    let progressionName: String = controls?["progression"]?.asString ?? "warm"
    let progression = progressionFor(mode: keyInfo.mode, name: progressionName)
    var previousVoicing: [Double]? = nil

    for bar in 0..<Int(bars) {
        let base = Double(bar * 4)
        let degree = progression[(bar / 2) % 4]
        let last = bar == Int(bars) - 1

        var kickSteps: [Double]
        switch style {
        case "house": kickSteps = [0, 4, 8, 12]
        case "hiphop": kickSteps = [0, 6, 8, 11]
        case "ambient": kickSteps = [0]
        default: kickSteps = [0, 7, 10]
        }
        var effectiveKick = kickSteps
        if let cx = complexity, cx < 30 {
            effectiveKick = style == "house" ? kickSteps : (style == "ambient" ? [0] : [0, 8])
        } else if let cx = complexity, cx > 75, style == "house" {
            effectiveKick = kickSteps + [15]
        }
        for (index, s) in effectiveKick.enumerated() {
            let v = style == "ambient" ? 65 : 100 - Double(index) * 6 + random() * 12
            add(&tracks[kick], pitch: 36, start: base + s * 0.25, duration: 0.13, velocity: v)
        }

        if style != "ambient" {
            for beat in [1.0, 3.0] {
                add(&tracks[snare], pitch: 38, start: base + beat, duration: 0.14, velocity: 85 + random() * 15)
            }
        }
        if style == "lofi" && bar % 2 == 1 && (complexity == nil || complexity! >= 45) {
            add(&tracks[snare], pitch: 38, start: base + 2.75, duration: 0.13, velocity: 35 + random() * 15)
        }
        let hStep: Double = (style == "house" || (complexity.map { $0 >= 60 } ?? false)) ? 1 : 2
        var s = 0.0
        while s < 16 {
            if style == "ambient" && s != 6 && s != 14 { s += hStep; continue }
            if style == "lofi" && random() < 0.10 && s != 0 { s += hStep; continue }
            let v: Double
            if style == "house" {
                v = Int(s) % 4 == 2 ? 78 : 43
            } else {
                v = (Int(s) % 4 == 0 ? 60 : 37) + random() * 16
            }
            add(&tracks[hat], pitch: 42, start: base + s * 0.25, duration: 0.08, velocity: v)
            s += hStep
        }
        if last && style != "ambient" && (complexity == nil || complexity! >= 65) {
            add(&tracks[snare], pitch: 38, start: base + 3.5, duration: 0.13, velocity: 60)
            add(&tracks[snare], pitch: 38, start: base + 3.75, duration: 0.13, velocity: 72)
        }

        let root = scalePitch(key: key, degree: degree, octave: -1)
        var bassEvents: [(Double, Double)]
        switch style {
        case "house": bassEvents = [(0, 0.75), (1, 0.5), (1.75, 0.25), (2, 0.75), (3, 0.5), (3.75, 0.25)]
        case "ambient": bassEvents = [(0, 3.8)]
        default: bassEvents = [(0, 1.35), (1.75, 0.5), (2.5, 0.9), (3.5, 0.4)]
        }
        if let cx = complexity, cx < 25 {
            bassEvents = [(0, 3.5)]
        }
        for (idx, event) in bassEvents.enumerated() {
            let pitch = root + (idx == 2 ? 7 : 0)
            add(&tracks[bass], pitch: pitch, start: base + event.0, duration: event.1, velocity: 78 + random() * 14)
        }

        var extra: [Int] = []
        if let cx = complexity {
            if cx >= 60 { extra = [6] }
        } else if style == "house" {
            extra = []
        } else {
            extra = [6]
        }
        var pitches = ([0, 2, 4] + extra).map { scalePitch(key: key, degree: degree + $0, octave: 0) }
        if controls?["voiceLeading"]?.asBool == true {
            pitches = voiceLead(pitches, previous: previousVoicing)
            previousVoicing = pitches
        }
        let chordStarts: [Double]
        switch style {
        case "house": chordStarts = [0.5, 1.5, 2.5, 3.5]
        case "ambient": chordStarts = [0]
        default:
            if let cx = complexity, cx < 25 { chordStarts = [0] } else { chordStarts = [0, 2.5] }
        }
        for start in chordStarts {
            for (j, p) in pitches.enumerated() {
                let dur = style == "ambient" ? 3.8 : (style == "house" ? 0.4 : (start == 0 ? 2.1 : 1.35))
                let v = style == "ambient" ? 48 : 57 - Double(j) * 3 + random() * 10
                add(&tracks[chords], pitch: p, start: base + start, duration: dur, velocity: v)
            }
        }

        let rhythm: [Double]
        if style == "ambient" {
            rhythm = [1, 3]
        } else if let cx = complexity, cx < 30 {
            rhythm = [0.5, 2.5]
        } else if bar % 2 == 0 {
            rhythm = [0.5, 1.25, 2.5, 3.25]
        } else {
            rhythm = [0, 0.75, 1.5, 2.75]
        }
        let contour: [Int]
        if bar % 4 == 3 { contour = [4, 2, 1, 0] }
        else if bar % 4 == 2 { contour = [2, 4, 6, 4] }
        else { contour = [4, 2, 4, 6] }
        for (idx, beat) in rhythm.enumerated() {
            if random() < 0.12 && idx != 0 { continue }
            let extraDegree = random() > (complexity.map { $0 < 30 ? 1.0 : 0.8 } ?? 0.8) ? 1 : 0
            let melodicDegree = degree + contour[idx] + extraDegree
            let dur = style == "ambient" ? 0.8 : (idx == 3 ? 0.65 : 0.45)
            let v = style == "ambient" ? 45 : 60 + random() * 16
            add(&tracks[lead], pitch: scalePitch(key: key, degree: melodicDegree, octave: 1), start: base + beat, duration: dur, velocity: v)
        }
    }

    if style == "ambient" {
        tracks[kick]["volume"] = .number(0.46)
        tracks[hat]["volume"] = .number(0.24)
        tracks[snare]["volume"] = .number(0.35)
        tracks[bass]["volume"] = .number(0.50)
        tracks[chords]["volume"] = .number(0.52)
        tracks[lead]["volume"] = .number(0.50)
    }

    var generated = JSONObject()
    generated["version"] = .number(2)
    generated["id"] = .string(jsUid())
    let styleNames = ["lofi": "午夜漫游", "hiphop": "街角节拍", "house": "微光舞池", "ambient": "云层之间"]
    generated["name"] = .string(options.name ?? (styleNames[style] ?? "未命名作品"))
    generated["style"] = .string(style)
    generated["key"] = .string(key)
    generated["bars"] = .number(bars)
    generated["bpm"] = .number(options.bpm ?? specBpm)
    generated["swing"] = .number(style == "house" ? 0 : style == "ambient" ? 5 : 12)
    generated["master"] = .number(0.75)
    generated["seed"] = .number(Double(seed))
    generated["tracks"] = .array(tracks.map { .object($0) })
    try ensureClips(&generated, strict: false)

    if let controls = controls {
        generated["composition"] = .object(controls)
        try applyPerformance(&generated, controls: controls, density: true)
    }
    return try validateProject(.object(generated))
}

private func styleTable() throws -> [String] { Tables.shared.styles.map(\.id) }
private func styleTableSpecs() -> [(id: String, bpm: Double)] {
    Tables.shared.styles.map { ($0.id, $0.bpm) }
}
