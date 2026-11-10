// 工程库文件存储测试:创建/保存/打开/版本/限额/归档。
import XCTest
import Foundation
@testable import SproutKit

final class VaultTests: XCTestCase {
    var vault: VaultStore!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sprout-vault-test-\(UUID().uuidString)", isDirectory: true)
        vault = VaultStore(root: dir)
    }

    func testCreateOpenAndSave() throws {
        let entry = try vault.create(name: "测试作品", bpm: 96, key: "C major", bars: 16)
        let opened = try vault.open(id: entry.id)
        XCTAssertNotNil(opened)
        XCTAssertEqual(opened?["name"]?.asString, "测试作品")
        XCTAssertEqual(opened?["key"]?.asString, "C major")
        // 保存更新名称
        var next = opened!
        next["name"] = .string("改名了")
        try vault.save(id: entry.id, project: next, autoVersion: false)
        let again = try vault.open(id: entry.id)
        XCTAssertEqual(again?["name"]?.asString, "改名了")
        XCTAssertEqual(try vault.library().first?.name, "改名了")
    }

    func testCheckpointAndRestore() throws {
        let entry = try vault.create(name: "版本测试", bpm: 90, key: "A minor", bars: 8)
        try vault.checkpoint(id: entry.id, project: try XCTUnwrap(try vault.open(id: entry.id)), label: "第一版")
        var next = try XCTUnwrap(try vault.open(id: entry.id))
        var note = JSONObject()
        note["id"] = .string("n1")
        note["pitch"] = .number(60)
        note["start"] = .number(0)
        note["duration"] = .number(1)
        note["velocity"] = .number(100)
        var list = (next["tracks"]?.asArray ?? [])
        if var t = list[0].asObject {
            t["notes"] = .array([.object(note)])
            list[0] = .object(t)
        }
        next["tracks"] = .array(list)
        next = try validateProject(.object(next))
        try vault.save(id: entry.id, project: next, autoVersion: false)
        try vault.checkpoint(id: entry.id, project: next, label: "第二版")
        let versions = try vault.versions(entry.id)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].label, "第二版")
        let restored = try vault.versionProject(id: entry.id, versionId: versions[1].id)
        XCTAssertEqual(restored?["tracks"]?.asArray?[0].asObject?["notes"]?.asArray?.count, 0)
    }

    func testProjectCap() throws {
        for i in 0..<12 {
            _ = try vault.create(name: "工程\(i)", bpm: 90, key: "A minor", bars: 8)
        }
        XCTAssertThrowsError(try vault.create(name: "第十三个", bpm: 90, key: "A minor", bars: 8))
        // 归档也计数
        try vault.setArchived(id: try vault.library()[0].id, archived: true)
        XCTAssertThrowsError(try vault.create(name: "还是不行", bpm: 90, key: "A minor", bars: 8))
        XCTAssertEqual(try vault.library().count, 12)
    }

    func testVersionPrune() throws {
        let entry = try vault.create(name: "裁剪", bpm: 90, key: "A minor", bars: 8)
        let project = try XCTUnwrap(try vault.open(id: entry.id))
        for i in 0..<30 {
            try vault.checkpoint(id: entry.id, project: project, label: "v\(i)")
        }
        let versions = try vault.versions(entry.id)
        XCTAssertEqual(versions.count, VaultLimits.versions)
        XCTAssertEqual(versions.first?.label, "v29")
        XCTAssertEqual(versions.last?.label, "v6")
    }

    func testImport() throws {
        let entry = try vault.create(name: "原稿", bpm: 90, key: "A minor", bars: 8)
        let project = try XCTUnwrap(try vault.open(id: entry.id))
        let imported = try vault.importProject(project, name: "副本")
        XCTAssertNotEqual(imported.id, entry.id)
        let opened = try XCTUnwrap(try vault.open(id: imported.id))
        XCTAssertEqual(opened["name"]?.asString, "副本")
        XCTAssertEqual(opened["id"]?.asString, imported.id)
    }
}
