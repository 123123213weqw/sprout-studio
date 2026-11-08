// 语义单元测试:数字格式、FNV link ID、校验拒绝路径(错误文案是契约)。
import XCTest
@testable import SproutKit

final class ValidationTests: XCTestCase {

    // MARK: - 数字格式(JSON.stringify 兼容)

    func testJsNumber() {
        XCTAssertEqual(jsNumber(0.62), "0.62")
        XCTAssertEqual(jsNumber(18000), "18000")
        XCTAssertEqual(jsNumber(0.03125), "0.03125")
        XCTAssertEqual(jsNumber(0), "0")
        XCTAssertEqual(jsNumber(-0.0), "0")
        XCTAssertEqual(jsNumber(0.0001), "0.0001")
        XCTAssertEqual(jsNumber(4294967295), "4294967295")
        XCTAssertEqual(jsNumber(86.5), "86.5")
    }

    func testRoundTripFormatting() throws {
        let json = #"{"a":0.62,"b":18000,"c":0.03125,"d":"底鼓","e":[1,2.5]}"#
        let value = try parseJSON(json)
        // 期望值由 node JSON.stringify(x, null, 2) 生成
        XCTAssertEqual(jsStringify(value), "{\n  \"a\": 0.62,\n  \"b\": 18000,\n  \"c\": 0.03125,\n  \"d\": \"底鼓\",\n  \"e\": [\n    1,\n    2.5\n  ]\n}")
    }

    // MARK: - FNV link ID(期望值由 node patterns-core.js 生成)

    func testInstanceNoteId() {
        XCTAssertEqual(instanceNoteId("clip-1", "pat-1", "note-1"), "link_3831b293340d0530")
        XCTAssertEqual(instanceNoteId("c", "p", "n"), "link_31819ba65f31bc40")
        XCTAssertEqual(instanceNoteId("clipA_1-B", "pat.X", "n-0123456789abcdef"), "link_8f8fca3e37d941a3")
    }

    // MARK: - 拒绝路径

    private func project(_ mutate: (inout JSONObject) -> Void) throws -> JSONValue {
        var p = JSONObject()
        p["version"] = .number(2)
        p["id"] = .string("test-1")
        p["name"] = .string("测试")
        p["style"] = .string("lofi")
        p["key"] = .string("A minor")
        p["bars"] = .number(8)
        p["bpm"] = .number(90)
        p["swing"] = .number(12)
        p["master"] = .number(0.75)
        p["seed"] = .number(271828)
        var track = JSONObject()
        track["id"] = .string("t1")
        track["instrument"] = .string("kick")
        track["notes"] = .array([])
        track["clips"] = .array([])
        p["tracks"] = .array([.object(track)])
        mutate(&p)
        return .object(p)
    }

    private func expectError(_ value: JSONValue, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try validateProject(value)
            XCTFail("应当抛错:\(message)", file: file, line: line)
        } catch let e as SproutError {
            XCTAssertEqual(e.message, message, file: file, line: line)
        } catch {
            XCTFail("错误类型不对:\(error)", file: file, line: line)
        }
    }

    func testRejections() throws {
        expectError(.null, "工程格式不正确")
        expectError(.array([]), "工程格式不正确")
        expectError(try project { $0["bars"] = .number(12) }, "工程长度必须为 4、8、16、32 或 64 小节")
        expectError(try project { $0["bpm"] = .number(300) }, "速度须在 40–200 BPM 之间")
        expectError(try project { $0["key"] = .string("B minor") }, "暂不支持这个调性")
        expectError(try project { $0["tracks"] = .array([]) }, "轨道数量须在 1–16 之间")
        // v3 必须带 Pattern 库
        expectError(try project { $0["version"] = .number(3) }, "共享 Pattern 工程须使用版本 3 和完整 Pattern 库")
        // 不支持的音源
        expectError(try project {
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            t["instrument"] = .string("guzheng")
            $0["tracks"] = .array([.object(t)])
        }, "工程包含不支持的音源")
        // 音符范围
        expectError(try project {
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            t["notes"] = .array([.object(note(pitch: 200, start: 0, duration: 0.25, velocity: 100))])
            $0["tracks"] = .array([.object(t)])
        }, "音符数据不合法")
        // 人性化偏移越界
        expectError(try project {
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            var n = note(pitch: 36, start: 0, duration: 0.25, velocity: 100)
            n["timingOffset"] = .number(0.5)
            t["notes"] = .array([.object(n)])
            $0["tracks"] = .array([.object(t)])
        }, "人性化偏移数据不合法")
        // loopRange 额外字段
        expectError(try project {
            var r = JSONObject()
            r["start"] = .number(0); r["end"] = .number(4); r["extra"] = .number(1)
            $0["loopRange"] = .object(r)
        }, "练习范围须在工程内，且至少为四分之一拍")
    }

    private func note(pitch: Double, start: Double, duration: Double, velocity: Double) -> JSONObject {
        var n = JSONObject()
        n["id"] = .string(jsUid())
        n["pitch"] = .number(pitch)
        n["start"] = .number(start)
        n["duration"] = .number(duration)
        n["velocity"] = .number(velocity)
        return n
    }

    // MARK: - 规范化行为

    func testMinimalProjectGetsClipsAndVersionBump() throws {
        // v1 且轨道完全没有 clips 字段 → v2,自动建整段音块
        let out = try validateProject(try project {
            $0["version"] = .number(1)
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            t["clips"] = nil
            $0["tracks"] = .array([.object(t)])
        })
        XCTAssertEqual(out["version"]?.asNumber, 2)
        let track = out["tracks"]?.asArray?[0].asObject
        let clips = track?["clips"]?.asArray ?? []
        XCTAssertEqual(clips.count, 1) // v1 span = 整个工程(32 拍)
        XCTAssertEqual(clips.first?.asObject?["start"]?.asNumber, 0)
        XCTAssertEqual(clips.first?.asObject?["length"]?.asNumber, 32)
    }

    func testV2ProjectAutoBuildsEightBeatClips() throws {
        let out = try validateProject(try project {
            $0["version"] = .number(2)
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            t["clips"] = nil
            $0["tracks"] = .array([.object(t)])
        })
        XCTAssertEqual(out["version"]?.asNumber, 2)
        let clips = out["tracks"]?.asArray?[0].asObject?["clips"]?.asArray ?? []
        XCTAssertEqual(clips.count, 4) // v2 span = 8 拍 → 32/8 = 4 块
        XCTAssertEqual(clips.first?.asObject?["start"]?.asNumber, 0)
        XCTAssertEqual(clips.first?.asObject?["length"]?.asNumber, 8)
    }

    func testDrumPitchForcedToMetaPitch() throws {
        let out = try validateProject(try project {
            var t = ($0["tracks"]?.asArray?[0].asObject)!
            t["notes"] = .array([.object(note(pitch: 40, start: 0, duration: 0.25, velocity: 100))])
            t["clips"] = .array([clip(id: "c1", start: 0, length: 8)])
            $0["tracks"] = .array([.object(t)])
        })
        XCTAssertEqual(out["tracks"]?.asArray?[0].asObject?["notes"]?.asArray?[0].asObject?["pitch"]?.asNumber, 36)
    }

    private func clip(id: String, start: Double, length: Double) -> JSONValue {
        var c = JSONObject()
        c["id"] = .string(id)
        c["name"] = .string("块")
        c["start"] = .number(start)
        c["length"] = .number(length)
        c["muted"] = .bool(false)
        return .object(c)
    }
}
