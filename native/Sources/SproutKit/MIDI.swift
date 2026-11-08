// SMF 编解码。对应 dist/music.js 的 encodeMIDI 与 dist/midi.js 的 decodeMIDI。
// 输出经 validateProject,错误文案与警告文案是契约。

import Foundation

// MARK: - 字节工具

private func u16(_ n: Int) -> [UInt8] { [UInt8((n >> 8) & 255), UInt8(n & 255)] }
private func u32(_ n: Int) -> [UInt8] { [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)] }
private func midiVlq(_ n: Int) -> [UInt8] {
    var groups: [UInt8] = [UInt8(n & 127)]
    var rest = n >> 7
    while rest > 0 {
        groups.insert(UInt8((rest & 127) | 128), at: 0)
        rest >>= 7
    }
    return groups
}
private func midiChunk(_ type: String, _ bytes: [UInt8]) -> [UInt8] {
    Array(type.utf8) + u32(bytes.count) + bytes
}

// MARK: - encodeMIDI

public func encodeMIDI(_ project: JSONObject) throws -> [UInt8] {
    let p = try validateProject(.object(project))
    let ppq = 480
    let bpm = p["bpm"]?.asNumber ?? 120
    let key = p["key"]?.asString ?? "C major"
    let bars = Int(p["bars"]?.asNumber ?? 4)
    let swing = p["swing"]?.asNumber ?? 0
    let totalTicks = bars * 4 * ppq
    let tempo = Int((60000000 / bpm).rounded())
    let keySignatures: [String: [UInt8]] = [
        "A minor": [0, 1], "C major": [0, 0], "D minor": [255, 1],
        "E minor": [1, 1], "G major": [1, 0], "F major": [255, 0]
    ]
    let ks = keySignatures[key] ?? [0, 0]
    var conductor: [UInt8] = [0, 255, 89, 2, ks[0], ks[1], 0, 255, 81, 3]
    conductor += Array(u32(tempo)[1...])
    conductor += [0, 255, 88, 4, 4, 2, 24, 8]
    conductor += midiVlq(totalTicks)
    conductor += [255, 47, 0]
    var chunks: [[UInt8]] = [midiChunk("MTrk", conductor)]
    var melodicChannel = 0
    let tracks = (p["tracks"]?.asArray ?? []).compactMap(\.asObject)
    let programs: [String: Int] = ["bass": 33, "keys": 4, "lead": 80, "pad": 89, "pluck": 24]

    for t in tracks {
        let kind = t["kind"]?.asString ?? "tonal"
        let instrument = t["instrument"]?.asString ?? "lead"
        if kind != "drum" {
            if melodicChannel == 9 { melodicChannel += 1 }
            if melodicChannel > 15 { throw SproutError("标准 MIDI 最多支持 15 个非鼓音源，请减少乐器轨道") }
        }
        let channel: Int
        if kind == "drum" { channel = 9 } else { channel = melodicChannel; melodicChannel += 1 }
        let name = Array((t["name"]?.asString ?? "").utf8)
        struct EV { let tick: Int; let order: Int; let data: [UInt8] }
        var events: [EV] = []
        if kind != "drum" {
            var program = programs[instrument] ?? 0
            if let sampler = t["sampler"]?.asObject,
               let presetId = sampler["preset"]?.asString,
               let preset = Samples.shared.presets[presetId], let pr = preset.program {
                program = pr
            }
            events.append(EV(tick: 0, order: 0, data: [UInt8(192 | channel), UInt8(program)]))
        }
        let volume = Int(((t["volume"]?.asNumber ?? 0.7) * 127).rounded())
        let pan = Int((((t["pan"]?.asNumber ?? 0) + 1) * 63.5).rounded())
        events.append(EV(tick: 0, order: 0, data: [UInt8(176 | channel), 7, UInt8(volume)]))
        events.append(EV(tick: 0, order: 0, data: [UInt8(176 | channel), 10, UInt8(pan)]))

        let clips = (t["clips"]?.asArray ?? []).compactMap(\.asObject)
        for n in audibleNotes(t) {
            let clip = clipAt(clips, n["start"]?.asNumber ?? 0)
            var midiPitch = Int(n["pitch"]?.asNumber ?? 60)
            if kind == "drum", let sampler = t["sampler"]?.asObject,
               let presetId = sampler["preset"]?.asString,
               let preset = Samples.shared.presets[presetId], let mp = preset.midiPitch {
                midiPitch = mp
            }
            let pb = performanceBeat(n, swing, clip)
            let start = Int((pb * Double(ppq)).rounded())
            let end = min(totalTicks, Int(((pb + (n["duration"]?.asNumber ?? 0)) * Double(ppq)).rounded()))
            events.append(EV(tick: start, order: 2, data: [UInt8(144 | channel), UInt8(midiPitch), UInt8(Int(n["velocity"]?.asNumber ?? 100))]))
            events.append(EV(tick: max(start + 1, end), order: 1, data: [UInt8(128 | channel), UInt8(midiPitch), 0]))
        }
        events = stableSorted(events) { $0.tick != $1.tick ? $0.tick < $1.tick : $0.order < $1.order }
        var last = 0
        var bytes: [UInt8] = [0, 255, 3] + midiVlq(name.count) + name
        for e in events {
            bytes += midiVlq(e.tick - last)
            bytes += e.data
            last = e.tick
        }
        bytes += midiVlq(max(0, totalTicks - last)) + [255, 47, 0]
        chunks.append(midiChunk("MTrk", bytes))
    }
    var data = midiChunk("MThd", u16(1) + u16(chunks.count) + u16(ppq))
    for c in chunks { data += c }
    return data
}

// MARK: - decodeMIDI

/// note-on 事件对象:active 队列与轨道 notes 持有同一实例(FIFO 配对直接回写,与 JS 共享引用一致)。
private final class MNote {
    let pitch: Int
    let startTick: Int
    let velocity: Int
    var endTick: Int?
    init(pitch: Int, startTick: Int, velocity: Int) {
        self.pitch = pitch
        self.startTick = startTick
        self.velocity = velocity
    }
}

private final class ChannelState {
    let channel: Int
    var program = 0
    var firstProgram: Int? = nil
    var volume = 0.7
    var pan = 0.0
    var notes: [MNote] = []
    init(_ c: Int) { channel = c }
}

public struct MIDIDecodeResult {
    public let project: JSONObject
    public let report: JSONObject
}

/// +(x.toFixed(n)) 的通用化(decodeMIDI 的 bpm 用 3 位)。
func round4to(_ x: Double, _ n: Double) -> Double {
    jsToFixedValue(x, Int(n))
}

public func decodeMIDI(_ input: [UInt8], name: String = "导入的 MIDI") throws -> MIDIDecodeResult {
    let bytes = input
    if bytes.count > 5_000_000 { throw SproutError("MIDI 文件不能超过 5 MB") }
    func need(_ at: Int, _ len: Int, _ end: Int = bytes.count) throws {
        if at + len > end { throw SproutError("MIDI 文件被截断或事件长度不正确") }
    }
    func text(_ at: Int, _ len: Int) -> String {
        String(decoding: bytes[at..<min(at + len, bytes.count)], as: UTF8.self)
    }
    func u16be(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
    func u32be(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }

    try need(0, 14)
    if text(0, 4) != "MThd" { throw SproutError("不是标准 MIDI 文件（缺少 MThd）") }
    let headerLength = u32be(4)
    if headerLength < 6 { throw SproutError("MIDI 头部不正确") }
    try need(8, headerLength)
    let format = u16be(8), count = u16be(10), ppq = u16be(12)
    if format != 0 && format != 1 { throw SproutError("只支持标准 MIDI format 0 和 1，不支持独立多序列 format 2") }
    if count == 0 || count > 256 || (format == 0 && count != 1) { throw SproutError("MIDI 轨道数量不正确") }
    if ppq & 0x8000 != 0 { throw SproutError("暂不支持 SMPTE 时间码 MIDI，请在原软件转成 PPQ 后导入") }
    if ppq == 0 { throw SproutError("MIDI PPQ 不能为零") }

    var raw: [(state: ChannelState, name: String)] = []
    var tempos: [(tick: Int, us: Int)] = []
    var signatures: [(tick: Int, numerator: Int, denominator: Int)] = []
    var keyEvents: [(tick: Int, sf: Int, minor: Bool)] = []
    var flags = Set<String>()
    var offset = 8 + headerLength
    var eventCount = 0, unmatched = 0, unclosed = 0, noteCount = 0
    var lastTick = 0

    for index in 0..<count {
        while true {
            try need(offset, 8)
            let len = u32be(offset + 4)
            try need(offset + 8, len)
            if text(offset, 4) == "MTrk" { break }
            offset += 8 + len
        }
        let end = offset + 8 + u32be(offset + 4)
        var at = offset + 8
        var tick = 0
        var running = 0
        var trackName = ""
        var ended = false
        var states: [Int: ChannelState] = [:]
        var active: [String: [MNote]] = [:]

        func byte() throws -> Int {
            try need(at, 1, end)
            defer { at += 1 }
            return Int(bytes[at])
        }
        func vlq() throws -> Int {
            var result = 0
            for _ in 0..<4 {
                let b = try byte()
                result = result * 128 + (b & 127)
                if b & 128 == 0 { return result }
            }
            throw SproutError("MIDI 可变长整数超过 4 字节")
        }
        func state(_ channel: Int) -> ChannelState {
            if let s = states[channel] { return s }
            let s = ChannelState(channel)
            states[channel] = s
            return s
        }

        while at < end {
            eventCount += 1
            if eventCount > 200000 { throw SproutError("MIDI 事件过多（最多 200000）") }
            tick += try vlq()
            if tick > 1_000_000_000 { throw SproutError("MIDI 时间范围过大") }
            var status = try byte()
            if status < 128 {
                if running == 0 { throw SproutError("MIDI running status 没有前置状态") }
                at -= 1
                status = running
            }
            if status == 0xff {
                running = 0
                let type = try byte()
                let len = try vlq()
                try need(at, len, end)
                let data = Array(bytes[at..<at + len])
                at += len
                if type == 0x2f {
                    if len != 0 { throw SproutError("MIDI 结束事件长度不正确") }
                    ended = true
                    break
                }
                if type == 3 {
                    let decoded = String(decoding: data, as: UTF8.self)
                    let stripped = String(decoded.unicodeScalars.filter { $0.value > 0x1f }.map(String.init).joined())
                    trackName = jsSlice16(stripped, 40)
                }
                if type == 0x51 {
                    if len != 3 { throw SproutError("MIDI 速度事件长度不正确") }
                    let us = Int(data[0]) << 16 | Int(data[1]) << 8 | Int(data[2])
                    if us == 0 { throw SproutError("MIDI 速度不能为零") }
                    tempos.append((tick, us))
                }
                if type == 0x58 {
                    if len != 4 { throw SproutError("MIDI 拍号事件长度不正确") }
                    signatures.append((tick, Int(data[0]), 1 << Int(data[1])))
                }
                if type == 0x59 {
                    if len != 2 { throw SproutError("MIDI 调号事件长度不正确") }
                    let sfRaw = Int(data[0])
                    keyEvents.append((tick, sfRaw > 127 ? sfRaw - 256 : sfRaw, data[1] == 1))
                }
                continue
            }
            if status == 0xf0 || status == 0xf7 {
                running = 0
                let len = try vlq()
                try need(at, len, end)
                at += len
                flags.insert("sysex")
                continue
            }
            if status < 0x80 || status > 0xef { throw SproutError("MIDI 包含不支持的系统事件") }
            running = status
            let type = status >> 4, channel = status & 15
            let a = try byte()
            let b = (type == 0xc || type == 0xd) ? 0 : try byte()
            if a > 127 || b > 127 { throw SproutError("MIDI 通道事件数据不正确") }
            let s = state(channel)
            let noteKey = "\(channel):\(a)"
            if type == 9 && b > 0 {
                if s.firstProgram == nil { s.firstProgram = s.program }
                let n = MNote(pitch: a, startTick: tick, velocity: b)
                active[noteKey, default: []].append(n)
                s.notes.append(n)
                noteCount += 1
                if noteCount > 12000 { throw SproutError("MIDI 超过 12000 个音符上限") }
            } else if type == 8 || (type == 9 && b == 0) {
                if var queue = active[noteKey], !queue.isEmpty {
                    queue.removeFirst().endTick = tick
                    active[noteKey] = queue
                } else { unmatched += 1 }
            } else if type == 0xc {
                if s.firstProgram != nil && s.program != a { flags.insert("program") }
                s.program = a
            } else if type == 0xb {
                if !s.notes.isEmpty && (a == 7 || a == 10) { flags.insert("automation") }
                else if a == 7 { s.volume = Double(b) / 127 }
                else if a == 10 { s.pan = Double(b - 64) / 64 }
                if a == 64 || a == 66 || a == 67 { flags.insert("pedal") }
                else if a != 7 && a != 10 { flags.insert("controllers") }
            } else if type == 0xe { flags.insert("bend") }
            else if type == 0xa || type == 0xd { flags.insert("pressure") }
        }
        if !ended { flags.insert("missingEnd") }
        lastTick = max(lastTick, tick)
        for s in states.values where !s.notes.isEmpty {
            for n in s.notes where n.endTick == nil {
                n.endTick = max(n.startTick + 1, tick)
                unclosed += 1
            }
            raw.append((s, trackName.isEmpty ? "MIDI 轨道 \(index + 1)" : trackName))
        }
        offset = end
    }
    if raw.isEmpty { throw SproutError("MIDI 文件没有可导入的音符") }
    if offset < bytes.count { flags.insert("trailing") }

    tempos.sort { $0.tick < $1.tick }
    let tempoAtZero = tempos.last(where: { $0.tick == 0 })?.us ?? 500000
    let requestedBpm = 60000000.0 / Double(tempoAtZero)
    let bpm = clamp(round4to(requestedBpm, 3), 40, 200)
    let sourceBeats = Double(([lastTick] + raw.flatMap { $0.state.notes.compactMap(\.endTick) }).max() ?? 0) / Double(ppq)
    let sourceBars = max(1, Int((sourceBeats / 4 - 0.00001).rounded(.up)))
    let bars = Tables.shared.barLengths.first { $0 >= Double(sourceBars) }.map(Int.init) ?? Tables.shared.maxBars

    var key = "C major"
    let keyEvent = keyEvents.last(where: { $0.tick == 0 })
    if let keyEvent {
        let rootsMinor = ["A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯", "D♯", "A♯"]
        let rootsMajor = ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"]
        let roots = keyEvent.minor ? rootsMinor : rootsMajor
        let sfIdx = keyEvent.sf + 7
        if sfIdx >= 0 && sfIdx < roots.count {
            let label = roots[sfIdx] + (keyEvent.minor ? " minor" : " major")
            if Tables.shared.keys[label] != nil { key = label } else { flags.insert("key") }
        } else { flags.insert("key") }
    }

    var tracks: [JSONObject] = []
    var stats: [String: Double] = [
        "sourceNotes": Double(raw.reduce(0) { $0 + $1.state.notes.count }),
        "importedNotes": 0, "outOfRange": 0, "unsupportedDrums": 0,
        "trimmed": 0, "shortened": 0, "shortNotes": 0
    ]
    func bump(_ k: String) { stats[k, default: 0] += 1 }
    func instrumentFor(_ program: Int) -> String {
        let id = "fluid-" + String(format: "%03d", program)
        return Samples.shared.presets[id]?.instrument ?? "keys"
    }
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

    for (s, sname) in raw {
        var groups: [String: JSONObject] = [:]
        var groupOrder: [String] = []
        for n in s.notes {
            let start = round4(Double(n.startTick) / Double(ppq))
            let end = round4(Double(n.endTick!) / Double(ppq))
            if start > Double(bars * 4) - 0.03125 { bump("trimmed"); continue }
            let instrument: String
            if s.channel == 9 {
                switch n.pitch {
                case 35, 36: instrument = "kick"
                case 37, 38, 39, 40: instrument = "snare"
                case 42, 44, 46, 70: instrument = "hat"
                default: bump("unsupportedDrums"); continue
                }
            } else {
                if n.pitch < 24 || n.pitch > 108 { bump("outOfRange"); continue }
                instrument = instrumentFor(s.firstProgram ?? s.program)
            }
            if groups[instrument] == nil {
                var t = makeTrack(instrument)
                var nm = sname
                if s.channel == 9 && sname != (t["name"]?.asString ?? "") {
                    nm = sname + " · " + (t["name"]?.asString ?? "")
                }
                t["name"] = .string(jsSlice16(nm, 40))
                t["volume"] = .number(s.volume)
                t["pan"] = .number(clamp(s.pan, -1, 1))
                groups[instrument] = t
                groupOrder.append(instrument)
            }
            if end > Double(bars * 4) { bump("shortened") }
            var duration = min(end, Double(bars * 4)) - start
            if duration < 0.03125 { duration = 0.03125; bump("shortNotes") }
            var note = JSONObject()
            note["id"] = .string(jsUid())
            note["pitch"] = .number(s.channel == 9 ? (["kick": 36, "snare": 38, "hat": 42][instrument] ?? 36) : Double(n.pitch))
            note["start"] = .number(start)
            note["duration"] = .number(round4(duration))
            note["velocity"] = .number(Double(n.velocity))
            var arr = groups[instrument]!["notes"]?.asArray ?? []
            arr.append(.object(note))
            groups[instrument]!["notes"] = .array(arr)
            stats["importedNotes", default: 0] += 1
        }
        for id in groupOrder { tracks.append(groups[id]!) }
    }
    if tracks.isEmpty { throw SproutError("没有可用音符：仅支持音高 24–108 和底鼓、军鼓、踩镲") }
    if tracks.count > 16 { throw SproutError("映射后有 \(tracks.count) 条轨道，超过 16 条上限。请在原软件拆分导出。") }

    var warnings: [JSONValue] = [.string("声音会映射为内置合成音源，不会还原原软件的音色或效果。")]
    if sourceBars > Tables.shared.maxBars { warnings.append(.string("原文件约 \(sourceBars) 小节，仅导入前 64 小节（\(Int(stats["trimmed"] ?? 0)) 个音符超出范围）。")) }
    if Set(tempos.map(\.us)).count > 1 || tempos.contains(where: { $0.tick > 0 && $0.us != tempoAtZero }) {
        warnings.append(.string("原文件含速度变化；本版按起始速度播放，音符的拍位置不变。"))
    }
    if bpm != round4to(requestedBpm, 3) { warnings.append(.string("原速度 \(String(format: "%.1f", requestedBpm)) BPM 已限制到 \(jsNumber(bpm)) BPM。")) }
    if signatures.contains(where: { $0.numerator != 4 || $0.denominator != 4 }) {
        warnings.append(.string("原文件含非 4/4 拍号；本版用每 4 拍一小节显示，不移动音符。"))
    }
    if flags.contains("key") { warnings.append(.string("原调号暂不支持，显示为 C 大调；音高原样保留，不自动转调。")) }
    if keyEvents.contains(where: { $0.tick > 0 }) { warnings.append(.string("调号变化仅作音符保留；当前只显示起始调性。")) }
    if keyEvent == nil { warnings.append(.string("未指定调号，显示为 C 大调；不会改变音高。")) }
    if (stats["unsupportedDrums"] ?? 0) > 0 { warnings.append(.string("\(jsNumber(stats["unsupportedDrums"]!)) 个其他打击乐音符未导入；只映射底鼓、军鼓和踩镲。")) }
    if (stats["outOfRange"] ?? 0) > 0 { warnings.append(.string("\(jsNumber(stats["outOfRange"]!)) 个超出音高 24–108 的音符未导入。")) }
    if (stats["shortened"] ?? 0) > 0 { warnings.append(.string("\(jsNumber(stats["shortened"]!)) 个跨工程终点的音符已裁短。")) }
    if (stats["shortNotes"] ?? 0) > 0 { warnings.append(.string("\(jsNumber(stats["shortNotes"]!)) 个极短音符延长到 1/128 全音符。")) }
    if flags.contains("program") { warnings.append(.string("轨道中途换音色使用第一次发声时的音色映射。")) }
    if !flags.isDisjoint(with: ["automation", "pedal", "controllers", "bend", "pressure", "sysex"]) {
        warnings.append(.string("音量/声像自动化、踏板、弯音、触后及 SysEx 暂未还原；只保留初始混音和音符。"))
    }
    if unclosed > 0 { warnings.append(.string("\(unclosed) 个未配对的 note-on 已在轨道末尾结束。")) }
    if unmatched > 0 { warnings.append(.string("\(unmatched) 个无对应 note-on 的 note-off 已忽略。")) }
    if flags.contains("missingEnd") { warnings.append(.string("部分轨道缺少结束标记，已按轨道数据边界恢复。")) }
    if flags.contains("trailing") { warnings.append(.string("已忽略轨道之后的附加数据。")) }

    for i in tracks.indices {
        var clip = JSONObject()
        clip["id"] = .string(jsUid())
        clip["name"] = tracks[i]["name"]!
        clip["start"] = .number(0)
        clip["length"] = .number(Double(bars * 4))
        clip["muted"] = .bool(false)
        tracks[i]["clips"] = .array([.object(clip)])
    }

    var projectName = name
    if let range = projectName.range(of: #"\.(mid|midi)$"#, options: [.regularExpression, .caseInsensitive]) {
        projectName.removeSubrange(range)
    }
    var project = JSONObject()
    project["version"] = .number(2)
    project["id"] = .string(jsUid())
    project["name"] = .string(jsSlice16(projectName, 60))
    project["style"] = .string("lofi")
    project["key"] = .string(key)
    project["bars"] = .number(Double(bars))
    project["bpm"] = .number(bpm)
    project["swing"] = .number(0)
    project["master"] = .number(0.75)
    project["seed"] = .number(1)
    project["tracks"] = .array(tracks.map { .object($0) })

    var report = JSONObject()
    report["format"] = .number(Double(format))
    report["ppq"] = .number(Double(ppq))
    report["sourceBars"] = .number(Double(sourceBars))
    report["bars"] = .number(Double(bars))
    report["bpm"] = .number(bpm)
    report["key"] = .string(key)
    report["tracks"] = .number(Double(tracks.count))
    for k in ["sourceNotes", "importedNotes", "outOfRange", "unsupportedDrums", "trimmed", "shortened", "shortNotes"] {
        report[k] = .number(stats[k] ?? 0)
    }
    report["warnings"] = .array(warnings)

    let validated = try validateProject(.object(project))
    return MIDIDecodeResult(project: validated, report: report)
}
