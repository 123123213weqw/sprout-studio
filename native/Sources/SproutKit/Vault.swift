// 文件工程库:Application Support 下的 sprout-vault。
// 语义对齐 PROJECT-LIBRARY.md / storage.js 的限额:
//   最多 12 个工程(归档也计数)、每工程 3 MB、最近 24 个版本、版本总量 8 MiB。
// 版本从新到旧保留(boundedVersions);归档不删除数据;错误文案沿用 storage.js。

import Foundation

public struct VaultEntry: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var updatedAt: Double
    public var archived: Bool
    public var lastOpened: Double?

    public init(id: String, name: String, updatedAt: Double, archived: Bool = false, lastOpened: Double? = nil) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.archived = archived
        self.lastOpened = lastOpened
    }
}

public struct VaultVersion: Codable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let reason: String   // manual / auto / restore-before
    public let createdAt: Double
    public let size: Int
}

public enum VaultLimits {
    public static let projects = 12
    public static let versions = 24
    public static let versionBytes = 8 * 1024 * 1024
    public static let projectBytes = 3_000_000
}

public final class VaultStore {
    public let root: URL
    private var lastAutoVersion: [String: Double] = [:]
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("sprout-vault", isDirectory: true)
    }

    // MARK: - 路径

    private var indexURL: URL { root.appendingPathComponent("library.json") }
    private func dir(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    private func projectURL(_ id: String) -> URL { dir(id).appendingPathComponent("project.json") }
    private func versionsDir(_ id: String) -> URL { dir(id).appendingPathComponent("versions", isDirectory: true) }

    // MARK: - 目录

    public func library() throws -> [VaultEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([VaultEntry].self, from: data)) ?? []
    }

    private func writeIndex(_ entries: [VaultEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    // MARK: - 工程

    /// 空白工程(3 鼓 + 贝斯/电钢/旋律/铺底),经 validateProject 后入库。
    public func create(name: String, bpm: Double, key: String, bars: Double) throws -> VaultEntry {
        lock.lock(); defer { lock.unlock() }
        var entries = try library()
        if entries.count >= VaultLimits.projects {
            throw SproutError("工程库最多 \(VaultLimits.projects) 个工程(归档也计数)。请先归档或清理旧作品。")
        }
        let id = jsUid()
        var trackList: [JSONValue] = []
        for (instrument, defaults) in [("kick", 0.72), ("snare", 0.72), ("hat", 0.45), ("bass", 0.72), ("keys", 0.62), ("lead", 0.72), ("pad", 0.72)] {
            guard let meta = Tables.shared.instruments[instrument] else { continue }
            var track = JSONObject()
            track["id"] = .string(jsUid())
            track["instrument"] = .string(instrument)
            track["name"] = .string(meta.name)
            track["kind"] = .string(meta.kind)
            track["color"] = .string(meta.color)
            track["volume"] = .number(defaults)
            track["pan"] = .number(instrument == "hat" ? 0.18 : instrument == "lead" ? 0.12 : 0)
            track["muted"] = .bool(false)
            track["solo"] = .bool(false)
            track["notes"] = .array([])
            trackList.append(.object(track))
        }
        var project = JSONObject()
        project["version"] = .number(2)
        project["id"] = .string(id)
        project["name"] = .string(jsSlice16(name.isEmpty ? "未命名作品" : name, 60))
        project["style"] = .string("lofi")
        project["key"] = .string(Tables.shared.keys[key] != nil ? key : "A minor")
        project["bars"] = .number(validBars(bars) ? bars : 16)
        project["bpm"] = .number(clamp(bpm, 40, 200))
        project["swing"] = .number(0)
        project["master"] = .number(0.75)
        project["seed"] = .number(1)
        project["tracks"] = .array(trackList)

        let validated = try validateProject(.object(project))
        let now = Date().timeIntervalSince1970
        let entry = VaultEntry(id: id, name: validated["name"]?.asString ?? "未命名作品", updatedAt: now)
        entries.append(entry)
        try writeIndex(entries)
        try FileManager.default.createDirectory(at: dir(id), withIntermediateDirectories: true)
        try serializeProject(validated).write(to: projectURL(id), atomically: true, encoding: .utf8)
        return entry
    }

    /// 文件导入为新工程(独立标识)。
    @discardableResult
    public func importProject(_ project: JSONObject, name: String? = nil) throws -> VaultEntry {
        lock.lock(); defer { lock.unlock() }
        var entries = try library()
        if entries.count >= VaultLimits.projects {
            throw SproutError("工程库最多 \(VaultLimits.projects) 个工程(归档也计数)。请先归档或清理旧作品。")
        }
        var next = project
        let id = jsUid()
        next["id"] = .string(id)
        if let name = name { next["name"] = .string(jsSlice16(name, 60)) }
        let validated = try validateProject(.object(next))
        let now = Date().timeIntervalSince1970
        let entry = VaultEntry(id: id, name: validated["name"]?.asString ?? "未命名作品", updatedAt: now)
        entries.append(entry)
        try writeIndex(entries)
        try FileManager.default.createDirectory(at: dir(id), withIntermediateDirectories: true)
        try serializeProject(validated).write(to: projectURL(id), atomically: true, encoding: .utf8)
        return entry
    }

    public func open(id: String) throws -> JSONObject? {
        lock.lock(); defer { lock.unlock() }
        var entries = try library()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        guard let text = try? String(contentsOf: projectURL(id), encoding: .utf8) else { return nil }
        let project = try validateProject(try loadSprout(text: text))
        let now = Date().timeIntervalSince1970
        entries[index].lastOpened = now
        entries[index].updatedAt = now
        try writeIndex(entries)
        return project
    }

    /// 保存当前工程;autoVersion 时按 60 秒节流自动留版本。
    public func save(id: String, project: JSONObject, label: String = "自动保存", reason: String = "auto", autoVersion: Bool = true) throws {
        lock.lock(); defer { lock.unlock() }
        let payload = serializeProject(project)
        let bytes = payload.utf8.count
        if bytes > VaultLimits.projectBytes {
            throw SproutError("工程数据超过 3 MB，请减少音符或保存文件备份")
        }
        try payload.write(to: projectURL(id), atomically: true, encoding: .utf8)
        var entries = try library()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].name = project["name"]?.asString ?? entries[index].name
            entries[index].updatedAt = Date().timeIntervalSince1970
            try writeIndex(entries)
        }
        let now = Date().timeIntervalSince1970
        if autoVersion, (lastAutoVersion[id] ?? 0) < now - 60 {
            lastAutoVersion[id] = now
            try writeVersion(id: id, payload: payload, bytes: bytes, label: label, reason: reason, at: now)
        }
    }

    public func checkpoint(id: String, project: JSONObject, label: String) throws {
        lock.lock(); defer { lock.unlock() }
        let payload = serializeProject(project)
        let bytes = payload.utf8.count
        if bytes > VaultLimits.projectBytes {
            throw SproutError("工程数据超过 3 MB，请减少音符或保存文件备份")
        }
        try writeVersion(id: id, payload: payload, bytes: bytes, label: jsSlice16(label.isEmpty ? "我的保存点" : label, 60), reason: "manual", at: Date().timeIntervalSince1970)
    }

    private func versionsIndexURL(_ id: String) -> URL { versionsDir(id).appendingPathComponent("index.json") }

    private func readVersionIndex(_ id: String) -> [VaultVersion] {
        guard let data = try? Data(contentsOf: versionsIndexURL(id)),
              let list = try? JSONDecoder().decode([VaultVersion].self, from: data) else { return [] }
        return list
    }

    private func writeVersion(id: String, payload: String, bytes: Int, label: String, reason: String, at timestamp: Double) throws {
        try FileManager.default.createDirectory(at: versionsDir(id), withIntermediateDirectories: true)
        let versionId = String(format: "%.0f", timestamp * 1000)
        try payload.write(to: versionsDir(id).appendingPathComponent("\(versionId).json"), atomically: true, encoding: .utf8)
        var list = readVersionIndex(id)
        list.append(VaultVersion(id: versionId, label: label, reason: reason, createdAt: timestamp, size: bytes))
        // boundedVersions:从新到旧保留,超 24 个或总量超 8 MiB 的旧版本连同文件移除
        list.sort { $0.createdAt > $1.createdAt }
        var kept: [VaultVersion] = []
        var total = 0
        let fm = FileManager.default
        for version in list {
            if kept.count >= VaultLimits.versions || total + version.size > VaultLimits.versionBytes {
                try? fm.removeItem(at: versionsDir(id).appendingPathComponent("\(version.id).json"))
            } else {
                kept.append(version)
                total += version.size
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(kept).write(to: versionsIndexURL(id), options: .atomic)
    }

    public func versions(_ id: String) throws -> [VaultVersion] {
        readVersionIndex(id)
    }

    public func versionProject(id: String, versionId: String) throws -> JSONObject? {
        guard let text = try? String(contentsOf: versionsDir(id).appendingPathComponent("\(versionId).json"), encoding: .utf8) else { return nil }
        return try validateProject(try loadSprout(text: text))
    }


    // MARK: - 归档(不删除数据)

    public func setArchived(id: String, archived: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        var entries = try library()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].archived = archived
        try writeIndex(entries)
    }

    public func rename(id: String, name: String) throws {
        lock.lock(); defer { lock.unlock() }
        var entries = try library()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].name = jsSlice16(name, 60)
        try writeIndex(entries)
    }
}
