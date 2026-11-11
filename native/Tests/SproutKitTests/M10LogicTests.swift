// M10 对拍:Pattern 批量编排/实例操作 + 音色收藏往返(基准 m10-logic.json)。
import XCTest
import Foundation
@testable import SproutKit

final class M10LogicTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Canonical: Decodable {
        let arrange: [String: [String: String]]
    }

    func testPatternArrangeAndSoundBank() throws {
        let url = Self.repoRoot.appendingPathComponent("shared/canonical/m10-logic.json")
        let canonical = try JSONDecoder().decode(Canonical.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(canonical.arrange.count, 90)
        let examples = Self.repoRoot.appendingPathComponent("examples")
        var mismatches: [String] = []
        var checked = 0
        if let enumerator = FileManager.default.enumerator(at: examples, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent.hasSuffix(".sprout") {
                let rel = url.path.replacingOccurrences(of: examples.path + "/", with: "")
                guard let expected = canonical.arrange[rel],
                      let text = try? String(contentsOf: url, encoding: .utf8),
                      let project = try? validateProject(try loadSprout(text: text)) else { continue }
                let patterns = jarr(project["patterns"]).compactMap(jobj)
                if let source = patterns.first, let patternId = source["id"]?.asString {
                    let sourceKind = source["kind"]?.asString ?? "tonal"
                    let sourceInstrument = source["instrument"]?.asString ?? ""
                    for track in jarr(project["tracks"]).compactMap(jobj) {
                        guard let trackId = track["id"]?.asString else { continue }
                        let kind = track["kind"]?.asString ?? "tonal"
                        guard kind == sourceKind, kind != "drum" || track["instrument"]?.asString == sourceInstrument else { continue }
                        let instrument = track["instrument"]?.asString ?? "lead"
                        let cases: [(String, (JSONObject) throws -> JSONObject)] = [
                            ("series2", { p in try planPatternSeries(p, patternId: patternId, trackId: trackId, start: 0, count: 2, extend: true).project }),
                            ("series4-unlinked", { p in try planPatternSeries(p, patternId: patternId, trackId: trackId, start: jnum(p, "bars", 4) * 4, count: 4, linked: false, extend: true).project }),
                        ]
                        for (name, op) in cases {
                            let key = "\(instrument):\(name)"
                            guard let want = expected[key] else { continue }
                            checked += 1
                            do {
                                let result = try op(project)
                                let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result))))
                                if digest != want { mismatches.append("\(rel)/\(key)") }
                            } catch {
                                if !want.hasPrefix("error:") { mismatches.append("\(rel)/\(key): swift 抛错 \(error)") }
                            }
                        }
                        let refs = patternInstances(project, patternId: patternId)
                        if !refs.isEmpty {
                            for action in ["mute", "unmute", "detach", "delete"] {
                                let key = "\(instrument):inst-\(action)"
                                guard let want = expected[key] else { continue }
                                checked += 1
                                do {
                                    let result = try planPatternInstances(project, patternId: patternId, clipIds: refs.map(\.clipId), action: action)
                                    let digest = fnv32(jsCompactStringify(stripIdsAndPatternIds(.object(result))))
                                    if digest != want { mismatches.append("\(rel)/\(key)") }
                                } catch {
                                    if !want.hasPrefix("error:") { mismatches.append("\(rel)/\(key): swift 抛错 \(error)") }
                                }
                            }
                        }
                        break
                    }
                }
                // 音色收藏往返
                if expected["sounds-roundtrip"] != nil {
                    let soundTracks = jarr(project["tracks"]).compactMap(jobj).filter { $0.has("sound") }.prefix(2)
                    if soundTracks.count > 0 {
                        checked += 1
                        do {
                            var presets: [JSONObject] = []
                            for (i, t) in soundTracks.enumerated() {
                                var e = JSONObject()
                                e["id"] = .string("sb-\(i)")
                                e["name"] = t["name"] ?? .string("")
                                e["instrument"] = t["instrument"]!
                                e["sound"] = t["sound"]!
                                e["createdAt"] = .number(1000)
                                e["archived"] = .bool(false)
                                presets.append(e)
                            }
                            let file = try exportSoundFile(presets)
                            let back = try parseSoundFile(file)
                            var projection: [JSONValue] = []
                            for x in back {
                                var pair = JSONObject()
                                pair["instrument"] = x["instrument"]!
                                pair["sound"] = x["sound"] ?? .null
                                projection.append(.object(pair))
                            }
                            let digest = fnv32(jsCompactStringify(.array(projection)))
                            if digest != expected["sounds-roundtrip"] { mismatches.append("\(rel)/sounds-roundtrip") }
                        } catch {
                            if !(expected["sounds-roundtrip"] ?? "").hasPrefix("error:") {
                                mismatches.append("\(rel)/sounds-roundtrip: swift 抛错 \(error)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "批量编排不一致(\(mismatches.count)/\(checked)):\n" + mismatches.prefix(5).joined(separator: "\n"))
    }
}
