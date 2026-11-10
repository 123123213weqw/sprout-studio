// M5 对拍:generateFromPrompt(固定 controls.seed,基准 shared/canonical/m5-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M5LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let prompt: [String: String]
    }

    func testGenerateFromPromptDigests() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m5-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertEqual(canonical.prompt.count, 30)
        let files = ["palette-demo.sprout", "library-house.sprout", "song-sections-start.sprout"]
        let prompts = [
            "来一段温柔的雨夜 lo-fi,慢一点",
            "改成 house 舞曲,16 小节,126 bpm",
            "只要鼓更有力,半拍军鼓",
            "只改旋律,明亮一点,D 小调",
            "氛围空灵 32 小节,快一点",
        ]
        var controls = JSONObject()
        controls["seed"] = .number(7777)
        var mismatches: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent("examples/\(file)"), encoding: .utf8)
            let project = try validateProject(try loadSprout(text: text))
            for scope in ["all", "drums"] {
                for prompt in prompts {
                    let id = "\(file)|\(scope)|\(prompt)"
                    guard let expected = canonical.prompt[id] else { continue }
                    do {
                        let result = try generateFromPrompt(project, prompt, scope: scope, controls: controls)
                        let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result.project))))
                        if digest + "|" + result.summary != expected {
                            mismatches.append("\(id): swift=\(digest)|\(result.summary) js=\(expected)")
                        }
                    } catch {
                        if !expected.hasPrefix("error:") {
                            mismatches.append("\(id): swift 抛错 \(error)")
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "提示词引擎不一致(\(mismatches.count)):\n" + mismatches.prefix(3).joined(separator: "\n"))
    }
}
