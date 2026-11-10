// M3 灵感引擎对拍:generateProject 固定矩阵(基准 shared/canonical/m3-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M3LogicTests: XCTestCase {
    struct Canonical: Decodable {
        let generate: [String: String]
    }

    func testGenerateProjectDigests() throws {
        let url = M1TestsRoot.repoRoot.appendingPathComponent("shared/canonical/m3-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertEqual(canonical.generate.count, 288)

        let keys = ["A minor", "C major", "D minor", "E minor", "G major", "F major"]
        let compositions: [JSONObject?] = [nil, {
            var c = JSONObject()
            c["density"] = .number(80)
            c["complexity"] = .number(80)
            c["energy"] = .number(75)
            c["humanize"] = .number(25)
            c["progression"] = .string("lift")
            c["voiceLeading"] = .bool(false)
            c["seed"] = .number(424242)
            return c
        }()]
        var mismatches: [String] = []
        for style in ["lofi", "hiphop", "house", "ambient"] {
            for key in keys {
                for bars in [4.0, 8.0] {
                    for seed in [1, 271828, 999] {
                        for (ci, composition) in compositions.enumerated() {
                            let id = "\(style)|\(key)|\(Int(bars))|\(seed)|c\(ci)"
                            guard let expected = canonical.generate[id] else { continue }
                            do {
                                let project = try generateProject(GenerateOptions(
                                    style: style, key: key, bars: bars, seed: seed,
                                    composition: composition
                                ))
                                let digest = fnv32(jsCompactStringify(stripIds(.object(project))))
                                if digest != expected {
                                    mismatches.append("\(id): swift=\(digest) js=\(expected)")
                                }
                            } catch {
                                if !expected.hasPrefix("error:") {
                                    mismatches.append("\(id): swift 抛错 \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "生成摘要不一致(\(mismatches.count)/288):\n" + mismatches.prefix(4).joined(separator: "\n"))
    }
}

enum M1TestsRoot {
    static let repoRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}
