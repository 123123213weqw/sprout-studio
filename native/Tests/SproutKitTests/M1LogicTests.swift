// M1 纯逻辑对拍:transport / 采样选择 / 采样发声计划,与 tools/gen-m1-canonical.mjs
// 生成的 shared/canonical/m1-logic.json 逐摘要比较。输入矩阵两侧必须一致。
import XCTest
import Foundation
@testable import SproutKit

func fnv32(_ text: String) -> String {
    var hash: UInt32 = 0x811c9dc5
    for b in text.utf8 {
        hash ^= UInt32(b)
        hash = hash &* 0x01000193
    }
    return String(format: "%08x", hash)
}

func fnv32bytes(_ bytes: [UInt8]) -> String {
    var hash: UInt32 = 0x811c9dc5
    for b in bytes {
        hash ^= UInt32(b)
        hash = hash &* 0x01000193
    }
    return String(format: "%08x", hash)
}

/// 递归去掉所有 "id" 键(对拍时排除随机 uid)。
func stripIds(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let o):
        var out = JSONObject()
        for (k, v) in o.pairs where k != "id" { out[k] = stripIds(v) }
        return .object(out)
    case .array(let a):
        return .array(a.map(stripIds))
    default:
        return value
    }
}

final class M1LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let transport: [String: String]
        let sampler: [String: String]
        let voicePlan: [String: String]
        let midi: [String: MIDIDigest]
        struct MIDIDigest: Decodable {
            let encode: String
            let project: String?
            let report: String?
        }
    }

    func loadCanonical() throws -> Canonical {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m1-logic.json")
        return try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
    }

    func testTransportDigests() throws {
        let canonical = try loadCanonical()
        XCTAssertGreaterThanOrEqual(canonical.transport.count, 90)
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var checked = 0
        var mismatches: [String] = []
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.transport[rel] else { mismatches.append("\(rel): 基准缺失"); continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                let project = try validateProject(try loadSprout(text: text))
                let plan = try playbackPlan(project, range: project["loopRange"])
                let digest = fnv32(plan.digestLines.joined(separator: "\n"))
                if digest != expected { mismatches.append("\(rel): swift=\(digest) js=\(expected)") }
                checked += 1
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "transport 摘要不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }

    func testSamplerSelectionDigests() throws {
        let canonical = try loadCanonical()
        XCTAssertGreaterThanOrEqual(canonical.sampler.count, 179)
        let velocities = [1, 5, 13, 33, 53, 73, 93, 113, 127]
        var mismatches: [String] = []
        for (id, expected) in canonical.sampler {
            var lines: [String] = []
            for pitch in 24...108 {
                for v in velocities {
                    for take in [0, 1, 2] {
                        let picked = try pickSample(presetId: id, pitch: pitch, velocity: v, take: take)
                        lines.append("P|\(pitch)|\(v)|\(take)|\(picked.id)")
                        let layers = try sampleLayers(presetId: id, pitch: pitch, velocity: v, take: take)
                            .map { "\($0.asset.id):\(String(format: "%.6f", $0.weight))" }
                            .joined(separator: ";")
                        lines.append("L|\(pitch)|\(v)|\(take)|\(layers)")
                    }
                }
            }
            let digest = fnv32(lines.joined(separator: "\n"))
            if digest != expected { mismatches.append("\(id): swift=\(digest) js=\(expected)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "采样选择摘要不一致(\(mismatches.count)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }

    func testVoicePlanDigests() throws {
        let canonical = try loadCanonical()
        XCTAssertGreaterThanOrEqual(canonical.voicePlan.count, 179)
        var mismatches: [String] = []
        for (id, expected) in canonical.voicePlan {
            guard let preset = Samples.shared.presets[id] else { mismatches.append("\(id): Swift 侧缺少该 preset"); continue }
            var settings = JSONObject()
            settings["preset"] = .string(id)
            var lines: [String] = []
            for pitch in [24, 40, 55, 60, 67, 72, 79, 84, 96, 108] {
                for v in [1, 33, 64, 96, 127] {
                    let a = try pickSample(presetId: id, pitch: pitch, velocity: v)
                    let plan = try sampleVoicePlan(
                        instrument: preset.instrument, settings: .object(settings),
                        pitch: pitch, duration: 1.5, velocity: v,
                        bufferDuration: Double(a.frames) / a.sampleRate
                    )
                    lines.append("V|\(pitch)|\(v)|\(plan.asset.id)|rate:\(String(format: "%.6f", plan.rate))|end:\(String(format: "%.4f", plan.end))|rel:\(String(format: "%.4f", plan.releaseAt))|atk:\(String(format: "%.4f", plan.attack))|peak:\(String(format: "%.6f", plan.peak))|loop:\(plan.loop ? 1 : 0)")
                }
            }
            let digest = fnv32(lines.joined(separator: "\n"))
            if digest != expected { mismatches.append("\(id): swift=\(digest) js=\(expected)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "发声计划摘要不一致(\(mismatches.count)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }

    func testMIDIRoundTripDigests() throws {
        let canonical = try loadCanonical()
        XCTAssertGreaterThanOrEqual(canonical.midi.count, 90)
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.midi[rel] else { mismatches.append("\(rel): 基准缺失"); continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                let project = try validateProject(try loadSprout(text: text))
                let bytes = try encodeMIDI(project)
                if fnv32bytes(bytes) != expected.encode { mismatches.append("\(rel): encode 摘要不一致"); continue }
                if let wantProject = expected.project {
                    let hasNotes = (project["tracks"]?.asArray ?? []).contains { ($0.asObject?["notes"]?.asArray?.count ?? 0) > 0 }
                    XCTAssertTrue(hasNotes, "\(rel): JS 侧有解码基准但 Swift 侧认为无音符")
                    let decoded = try decodeMIDI(bytes)
                    if fnv32(jsCompactStringify(stripIds(.object(decoded.project)))) != wantProject {
                        mismatches.append("\(rel): 解码工程摘要不一致")
                    }
                    if fnv32(jsCompactStringify(.object(decoded.report))) != expected.report! {
                        mismatches.append("\(rel): 解码报告摘要不一致")
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "MIDI 摘要不一致(\(mismatches.count)):\n" + mismatches.prefix(8).joined(separator: "\n"))
    }

    func testEnvelopePlan() throws {
        var sound = JSONObject()
        sound["attack"] = .number(0.01)
        sound["decay"] = .number(0.3)
        sound["sustain"] = .number(0.5)
        sound["release"] = .number(0.2)
        let plan = try envelopePlan(duration: 1.0, sound: sound)
        XCTAssertEqual(plan.points.count, 5) // 0 / 起音 / 衰减 / 持续 / 释放归零
        XCTAssertEqual(plan.offLevel, 0.5, accuracy: 1e-12)
        XCTAssertEqual(plan.end, 1.2, accuracy: 1e-12)
        // 起音中提前松开
        let short = try envelopePlan(duration: 0.004, sound: sound)
        XCTAssertEqual(short.points[1].value, 0.4, accuracy: 1e-12)
    }
}
