// M9 对拍:表演整理(基准 shared/canonical/m9-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M9LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let performance: [String: [String: String]]
    }

    private func baseControls() -> JSONObject {
        var c = JSONObject()
        for (k, v) in performanceDefaults { c[k] = v }
        return c
    }

    func testPlanPerformanceDigests() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m9-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(canonical.performance.count, 90)
        let presets: [(String, [(String, JSONValue)])] = [
            ("tidy", [("grid", .number(0.25)), ("timing", .string("clear"))]),
            ("natural", [("timing", .string("natural")), ("timingAmount", .number(25)), ("velocitySpread", .number(5))]),
            ("soft", [("velocityScale", .number(80))]),
            ("strong", [("velocityScale", .number(120))]),
        ]
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        var checked = 0
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.performance[rel],
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      let project = try? validateProject(try loadSprout(text: text)) else { continue }
                var usedFirst = false
                for track in jarr(project["tracks"]).compactMap(jobj) {
                    let allNotes = jarr(track["notes"]).compactMap(jobj)
                    let selected = allNotes.prefix(8).map { $0["id"]?.asString ?? "" }
                    guard !selected.isEmpty else { continue }
                    if usedFirst { break }
                    usedFirst = true
                    let instrument = track["instrument"]?.asString ?? "lead"
                    let trackId = track["id"]?.asString ?? ""
                    for (name, fields) in presets + [("trim", [("grid", .number(0.25)), ("timing", .string("clear")), ("overlap", .string("trim")), ("timing", .string("natural"))])] {
                        let key = "\(instrument):\(name)"
                        guard let want = expected[key] else { continue }
                        checked += 1
                        var controls = baseControls()
                        for (k, v) in fields { controls[k] = v }
                        let scope = name == "trim" ? "track" : "selected"
                        do {
                            let result = try planPerformance(project, trackId: trackId, scope: scope,
                                                             ids: selected, controls: controls)
                            if let applied = result.project {
                                let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(applied))))
                                if digest != want { mismatches.append("\(rel)/\(key)") }
                            } else if !want.hasPrefix("blocked:") {
                                mismatches.append("\(rel)/\(key): swift blocked 而 js=\(want)")
                            } else if want != "blocked:" + result.report.blocked.joined(separator: ";") {
                                mismatches.append("\(rel)/\(key): blocked 理由不同")
                            }
                        } catch {
                            if !want.hasPrefix("error:") {
                                mismatches.append("\(rel)/\(key): swift 抛错 \(error)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "表演整理不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }
}
