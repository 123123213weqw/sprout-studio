// M0 出口判据:examples/ 全部 fixture 经 Swift validateProject/normalizePatterns 后,
// 与 shared/canonical/ 的 JS 规范输出逐字节一致,且校验幂等。
import XCTest
@testable import SproutKit

final class FixtureTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FixtureTests.swift
        .deletingLastPathComponent() // SproutKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // native

    func collectFixtures() -> [(rel: String, path: URL)] {
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var result: [(String, URL)] = []
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if url.lastPathComponent.hasSuffix(".sprout") || url.lastPathComponent.hasSuffix(".sprout-patterns") {
                    let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                    result.append((rel, url))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    func testAllFixturesMatchJSCanonical() throws {
        let fixtures = collectFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 90, "fixture 数量异常:examples/ 应有 96+ 个")

        var diffs: [String] = []
        var idempotenceFailures: [String] = []
        for fixture in fixtures {
            let text = try String(contentsOf: fixture.path, encoding: .utf8)
            let canonicalURL = Self.repoRoot.appendingPathComponent("shared/canonical/\(fixture.rel)")
            guard let canonical = try? String(contentsOf: canonicalURL, encoding: .utf8) else {
                diffs.append("\(fixture.rel): 缺少 canonical 基准")
                continue
            }
            do {
                let value = try loadSprout(text: text)
                let encoded: String
                if fixture.rel.hasSuffix(".sprout-patterns") {
                    encoded = serializePatterns(try validatePatternLibrary(value))
                } else {
                    encoded = serializeProject(try validateProject(value))
                }
                if encoded != canonical {
                    let a = Array(encoded.unicodeScalars), b = Array(canonical.unicodeScalars)
                    var idx = 0
                    while idx < a.count && idx < b.count && a[idx] == b[idx] { idx += 1 }
                    let lo = max(0, idx - 40)
                    let snippetA = String(String.UnicodeScalarView(a[lo..<min(a.count, idx + 40)]))
                    let snippetB = String(String.UnicodeScalarView(b[lo..<min(b.count, idx + 40)]))
                    diffs.append("\(fixture.rel) @char \(idx):\n  swift: …\(snippetA)…\n  js:    …\(snippetB)…")
                }
                // 幂等:对已规范化的输出再校验一次,应完全不变
                let reparsed = try loadSprout(text: encoded)
                let reencoded = fixture.rel.hasSuffix(".sprout-patterns")
                    ? serializePatterns(try normalizePatternArray(reparsed))
                    : serializeProject(try validateProject(reparsed))
                if reencoded != canonical { idempotenceFailures.append(fixture.rel) }
            } catch {
                diffs.append("\(fixture.rel): 校验抛错 \(error)")
            }
        }
        XCTAssertTrue(diffs.isEmpty, "与 JS 规范输出不一致(\(diffs.count) 个):\n" + diffs.prefix(8).joined(separator: "\n"))
        XCTAssertTrue(idempotenceFailures.isEmpty, "校验不幂等:\(idempotenceFailures)")
    }
}
