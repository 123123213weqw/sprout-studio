// M8 对拍:段落复制/移动/清空/删标签(基准 shared/canonical/m8-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M8LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let sectionOps: [String: [String: String]]
    }

    func testPlanSectionDigests() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m8-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(canonical.sectionOps.count, 40)

        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        var checked = 0
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.sectionOps[rel],
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      let project = try? validateProject(try loadSprout(text: text)),
                      let section = jarr(project["sections"]).first?.asObject,
                      let sectionId = section["id"]?.asString else { continue }
                let target = jnum(project, "bars", 4) * 4
                let cases: [(String, (JSONObject, String) throws -> JSONObject)] = [
                    ("copy-end", { p, sid in try planSection(p, sectionId: sid, action: "copy", start: target, extend: true).project }),
                    ("copy-linked", { p, sid in try planSection(p, sectionId: sid, action: "copy", start: target, linked: true, extend: true).project }),
                    ("move-end", { p, sid in try planSection(p, sectionId: sid, action: "move", start: target, extend: true).project }),
                    ("clear", { p, sid in try planSection(p, sectionId: sid, action: "clear").project }),
                    ("label-delete", { p, sid in try planSection(p, sectionId: sid, action: "label-delete").project }),
                ]
                for (name, op) in cases {
                    guard let want = expected["s0:\(name)"] else { continue }
                    checked += 1
                    do {
                        let result = try op(project, sectionId)
                        let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result))))
                        if digest != want { mismatches.append("\(rel)/\(name)") }
                    } catch {
                        if !want.hasPrefix("error:") {
                            mismatches.append("\(rel)/\(name): swift 抛错 \(error)")
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "段落操作不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }
}
