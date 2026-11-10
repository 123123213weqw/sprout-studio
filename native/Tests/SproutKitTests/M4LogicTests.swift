// M4 对拍:clip 操作与 Pattern CRUD(基准 shared/canonical/m4-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

func stripIdsAndPatternIds(_ value: JSONValue) -> JSONValue {
    switch value {
    case .object(let o):
        var out = JSONObject()
        for (k, v) in o.pairs where k != "id" && k != "patternId" {
            out[k] = stripIdsAndPatternIds(v)
        }
        return .object(out)
    case .array(let a):
        return .array(a.map(stripIdsAndPatternIds))
    default:
        return value
    }
}

final class M4LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let ops: [String: [String: String]]
    }

    private func loadProjects() -> [String: JSONObject] {
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
        return projects
    }

    func testClipAndPatternOps() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m4-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        let projects = loadProjects()
        XCTAssertGreaterThanOrEqual(canonical.ops.count, 90)

        var mismatches: [String] = []
        var checked = 0
        for (rel, expected) in canonical.ops {
            guard let p = projects[rel] else { continue }
            let tracks = jarr(p["tracks"]).compactMap(jobj)
            guard let track = tracks.first, let clip = jobj(jarr(track["clips"]).first ?? .null) else { continue }
            let trackId = track["id"]?.asString ?? ""
            let clipId = clip["id"]?.asString ?? ""
            let length = jnum(clip, "length", 4)
            let start = jnum(clip, "start")

            var cases: [String: Result<JSONObject, Error>] = [:]
            cases["resize"] = Result { try resizeClip(p, trackId: trackId, clipId: clipId, to: max(0.25, length - 1)) }
            cases["move"] = Result { try moveClip(p, trackId: trackId, clipId: clipId, to: start + 0.5).project }
            cases["split"] = Result { try splitClip(p, trackId: trackId, clipId: clipId, at: start + min(2, length / 2)).project }
            cases["repeat"] = Result { try repeatClip(p, trackId: trackId, clipId: clipId, count: 2).project }
            cases["update"] = Result { try updateClip(p, trackId: trackId, clipId: clipId, start: start, length: length, name: "改名", muted: true) }
            cases["remove"] = Result { try removeClip(p, trackId: trackId, clipId: clipId) }
            cases["capture"] = Result { try capturePattern(p, trackId: trackId, clipId: clipId, name: "测试乐句", linkSource: true).project }

            for (name, expectedDigest) in expected {
                guard let result = cases[name] else { continue }
                checked += 1
                switch result {
                case .success(let project):
                    if expectedDigest.hasPrefix("error:") {
                        mismatches.append("\(rel)/\(name): JS 抛错(\(expectedDigest)) Swift 成功")
                    } else {
                        let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(project))))
                        if digest != expectedDigest { mismatches.append("\(rel)/\(name): swift=\(digest) js=\(expectedDigest)") }
                    }
                case .failure(let error):
                    if !expectedDigest.hasPrefix("error:") {
                        mismatches.append("\(rel)/\(name): swift 抛错 \(error) 而 JS 成功")
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "操作摘要不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(6).joined(separator: "\n"))
    }
}
