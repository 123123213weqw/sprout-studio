// 离线渲染测试:合成工程(无需媒体)+ 采样工程(有媒体目录时)。
import XCTest
import Foundation
@testable import SproutAudio
@testable import SproutKit

final class RenderTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func loadProject(_ rel: String) throws -> JSONObject {
        let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(rel), encoding: .utf8)
        return try validateProject(try loadSprout(text: text))
    }

    func stats(_ wav: [UInt8]) -> (peak: Double, nonSilent: Bool) {
        var peak = 0.0
        var i = 44
        while i + 1 < wav.count {
            let raw = Int16(bitPattern: UInt16(wav[i]) | UInt16(wav[i + 1]) << 8)
            peak = max(peak, abs(Double(raw) / 32767))
            i += 2
        }
        return (peak, peak > 0.01)
    }

    func testSynthFixtureRender() throws {
        // 纯合成工程(无 sampler 字段,不需要媒体)
        let project = try loadProject("examples/service-demo.sprout")
        let hasSampler = (project["tracks"]?.asArray ?? []).contains { $0.asObject?.has("sampler") == true }
        XCTAssertFalse(hasSampler, "选一个纯合成 fixture")
        let (wav, renderStats) = try renderWAV(project, options: RenderOptions())
        XCTAssertGreaterThan(wav.count, 44 + 44100) // 至少一秒
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        let s = stats(wav)
        XCTAssertTrue(s.nonSilent, "输出不能是静音")
        XCTAssertLessThanOrEqual(s.peak, 1.0, "输出不能削波")
        XCTAssertEqual(Double(renderStats.frames), renderStats.seconds * 44100, accuracy: 1)
    }

    func testSampledFixtureRender() throws {
        let mediaRoot = URL(fileURLWithPath: "/Users/wangyue/ZCodeProject/sprout-media/app/dist/samples")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mediaRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw XCTSkip("本机媒体目录不存在,跳过采样渲染")
        }
        let project = try loadProject("examples/sound-library-v29/edm-sketch.sprout")
        let hasSampler = (project["tracks"]?.asArray ?? []).contains { $0.asObject?.has("sampler") == true }
        XCTAssertTrue(hasSampler, "选一个含 sampler 的 fixture")
        let (wav, renderStats) = try renderWAV(project, options: RenderOptions(samplesRoot: mediaRoot))
        let s = stats(wav)
        XCTAssertTrue(s.nonSilent, "输出不能是静音")
        XCTAssertLessThanOrEqual(s.peak, 1.0, "输出不能削波")
        XCTAssertGreaterThan(renderStats.seconds, 3, "尾部与正文都应在")
    }

    func testSha256KnownVector() {
        XCTAssertEqual(sha256Hex(Array("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testWavRoundTrip() throws {
        let buffer = SampleBuffer(frames: 16, sampleRate: 44100, channels: [(0..<16).map { Double($0) / 32 - 0.25 }])
        XCTAssertEqual(buffer.frames, 16)
        let left = (0..<100).map { sin(Double($0) * 0.1) * 0.5 }
        let right = (0..<100).map { cos(Double($0) * 0.1) * 0.5 }
        let wav = encodeWAV(left: left, right: right, sampleRate: 44100)
        XCTAssertEqual(wav.count, 44 + 400)
        var mono = wav
        mono[22] = 1 // channels=1
        mono[32] = 2 // align
        // 数据块长度仍是 200 帧×2 字节;byteRate 改为单声道值 88200
        let rate = 44100 * 2
        mono[28] = UInt8(rate & 255); mono[29] = UInt8((rate >> 8) & 255)
        mono[30] = UInt8((rate >> 16) & 255); mono[31] = 0
        XCTAssertNoThrow(try decodeSamplePCM(mono))
    }
}
