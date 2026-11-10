// M6 对拍:段落 CRUD/骨架 + 过门填充(基准 shared/canonical/m6-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M6LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let sections: [String: [String: String]]
    }

    func testSectionsAndFills() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m6-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(canonical.sections.count, 90)

        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        var checked = 0
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.sections[rel],
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      let project = try? validateProject(try loadSprout(text: text)) else { continue }

                // 骨架模板
                for tpl in ["verse-chorus", "four-parts"] {
                    guard let want = expected["tpl:\(tpl)"] else { continue }
                    checked += 1
                    do {
                        let result = try sectionTemplate(project, template: tpl)
                        let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result))))
                        if digest != want { mismatches.append("\(rel)/tpl:\(tpl)") }
                    } catch {
                        if !want.hasPrefix("error:") { mismatches.append("\(rel)/tpl:\(tpl): swift 抛错 \(error)") }
                    }
                }
                // 段落添加
                if let want = expected["add"] {
                    checked += 1
                    do {
                        let result = try updateSection(project, name: "新副歌", kind: "chorus", start: 0, length: 4)
                        let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result.project))))
                        if digest != want { mismatches.append("\(rel)/add") }
                    } catch {
                        if !want.hasPrefix("error:") { mismatches.append("\(rel)/add: swift 抛错 \(error)") }
                    }
                }
                // 过门
                if let sections = project["sections"]?.asArray, !sections.isEmpty,
                   let section = sections.last?.asObject, let sectionId = section["id"]?.asString {
                    let drumIds = jarr(project["tracks"]).compactMap { $0.asObject }
                        .filter { $0["kind"]?.asString == "drum" }
                        .map { $0["id"]?.asString ?? "" }
                    if !drumIds.isEmpty {
                        for style in ["gentle", "rise", "break"] {
                            for bars in [1, 2] {
                                guard let want = expected["fill:\(style):\(bars)"] else { continue }
                                checked += 1
                                var controls = JSONObject()
                                controls["style"] = .string(style)
                                controls["bars"] = .number(Double(bars))
                                controls["energy"] = .number(70)
                                controls["seed"] = .number(42)
                                controls["fillGaps"] = .bool(true)
                                do {
                                    let result = try planSectionFill(project, sectionId: sectionId, trackIds: drumIds, controls: controls)
                                    let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result.project))))
                                    if digest != want { mismatches.append("\(rel)/fill:\(style):\(bars)") }
                                } catch {
                                    if !want.hasPrefix("error:") { mismatches.append("\(rel)/fill:\(style):\(bars): swift 抛错 \(error)") }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "段落/过门不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }
}
