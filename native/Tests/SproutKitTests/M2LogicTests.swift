// M2 纯函数对拍:移调与长度调整(基准 shared/canonical/m2-logic.json,
// 由 tools/gen-m2-canonical.mjs 生成)。
import XCTest
import Foundation
@testable import SproutKit

final class M2LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let transpose: [String: TransposeDigest]
        let resize: [String: ResizeDigest]
        let soundPresets: [String: String]
        struct TransposeDigest: Decodable { let target: String; let digest: String }
        struct ResizeDigest: Decodable { let bars: Double; let digest: String?; let error: String? }
    }

    private func load() throws -> (Canonical, [String: JSONObject]) {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m2-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var projects: [String: JSONObject] = [:]
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   let project = try? validateProject(try loadSprout(text: text)) {
                    projects[rel] = project
                }
            }
        }
        return (canonical, projects)
    }

    func testSoundPresetDigests() throws {
        let (canonical, _) = try load()
        XCTAssertEqual(canonicalSafe(canonical).count, 24)
        var mismatches: [String] = []
        for (key, expected) in canonical.soundPresets ?? [:] {
            let parts = key.split(separator: ":").map(String.init)
            guard parts.count == 2, let preset = try? soundPreset(instrument: parts[0], id: parts[1]) else {
                mismatches.append("\(key): Swift 抛错")
                continue
            }
            let digest = fnv32(jsCompactStringify(.object(preset)))
            if digest != expected { mismatches.append("\(key): swift=\(digest) js=\(expected)") }
        }
        XCTAssertTrue(mismatches.isEmpty, "音色预设不一致:\(mismatches)")
    }

    private func canonicalSafe(_ c: Canonical) -> [String: String] { c.soundPresets ?? [:] }

    func testTransposeDigests() throws {
        let (canonical, projects) = try load()
        XCTAssertGreaterThanOrEqual(canonical.transpose.count, 90)
        var mismatches: [String] = []
        for (rel, expected) in canonical.transpose {
            guard let project = projects[rel] else { continue }
            do {
                let moved = try transposeProject(project, toKey: expected.target)
                let digest = fnv32(jsCompactStringify(stripIds(.object(moved))))
                if digest != expected.digest { mismatches.append("\(rel): swift=\(digest) js=\(expected.digest)") }
            } catch {
                mismatches.append("\(rel): 抛错 \(error)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "移调摘要不一致(\(mismatches.count)):\n" + mismatches.prefix(4).joined(separator: "\n"))
    }

    func testResizeDigests() throws {
        let (canonical, projects) = try load()
        XCTAssertGreaterThanOrEqual(canonical.resize.count, 90)
        var mismatches: [String] = []
        for (rel, expected) in canonical.resize {
            guard let project = projects[rel] else { continue }
            do {
                let grown = try resizeProject(project, toBars: expected.bars, fill: "repeat")
                if let want = expected.digest {
                    let digest = fnv32(jsCompactStringify(stripIds(.object(grown))))
                    if digest != want { mismatches.append("\(rel): swift=\(digest) js=\(want)") }
                } else {
                    mismatches.append("\(rel): JS 抛错但 Swift 成功")
                }
            } catch {
                if expected.digest != nil {
                    mismatches.append("\(rel): swift 抛错 \(error) 而 JS 成功")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "长度摘要不一致(\(mismatches.count)):\n" + mismatches.prefix(4).joined(separator: "\n"))
    }
}
