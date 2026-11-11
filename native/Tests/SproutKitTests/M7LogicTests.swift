// M7 对拍:乐句变换(基准 shared/canonical/m7-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M7LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let phrase: [String: [String: String]]
    }

    func testPhraseTransformDigests() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m7-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(canonical.phrase.count, 90)

        let variants: [(String, [(String, JSONValue)])] = [
            ("half", [("ratio", .number(0.5))]),
            ("double", [("ratio", .number(2)), ("extend", .bool(true))]),
            ("reverse", [("reverse", .bool(true))]),
            ("up12", [("transpose", .number(12))]),
            ("snap", [("transpose", .number(7)), ("scale", .string("A minor"))]),
            ("clear-timing", [("ratio", .number(0.5)), ("timing", .string("clear"))]),
        ]

        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        var checked = 0
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.phrase[rel],
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      let project = try? validateProject(try loadSprout(text: text)) else { continue }
                var seenInstruments = Set<String>()
                for track in jarr(project["tracks"]).compactMap(jobj) {
                    let instrumentKey = track["instrument"]?.asString ?? "lead"
                    guard !seenInstruments.contains(instrumentKey) else { continue }
                    seenInstruments.insert(instrumentKey)
                    guard let clip = jarr(track["clips"]).first?.asObject,
                          let trackId = track["id"]?.asString,
                          let clipId = clip["id"]?.asString else { continue }
                    let instrument = track["instrument"]?.asString ?? "lead"
                    for (name, fields) in variants {
                        let key = "\(instrument):\(name)"
                        guard let want = expected[key] else { continue }
                        checked += 1
                        var controls = JSONObject()
                        for (k, v) in fields { controls[k] = v }
                        do {
                            let result = try planPhraseTransform(project, trackId: trackId, clipId: clipId, controls: controls)
                            let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result.project))))
                            if digest != want { mismatches.append("\(rel)/\(key)") }
                        } catch {
                            if !want.hasPrefix("error:") {
                                mismatches.append("\(rel)/\(key): swift 抛错 \(error)")
                            }
                        }
                    }
                    break
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "乐句变换不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }
}
