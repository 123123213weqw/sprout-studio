// 工程库:列表/新建/导入/归档/版本浏览。
// 语义对齐 Web 版「我的工程」:文件导入成为新工程(独立标识);归档不删除;
// 版本恢复前会先给当前内容留「恢复版本前」快照。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit

struct LibraryView: View {
    @ObservedObject var model: PlayerModel
    @State private var entries: [VaultEntry] = []
    @State private var showNew = false
    @State private var versionsEntry: VaultEntry?

    private var active: [VaultEntry] { entries.filter { !$0.archived } }
    private var archived: [VaultEntry] { entries.filter { $0.archived } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("我的工程").font(.title2.bold())
                Text("\(entries.count)/\(VaultLimits.projects)(归档也计数)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showNew = true } label: { Label("新建", systemImage: "plus") }
                Button { importFile() } label: { Label("导入 .sprout", systemImage: "square.and.arrow.down") }
                Button("完成") { model.showLibrary = false }
            }
            .padding(12)

            List {
                Section("作品") {
                    ForEach(active) { entry in
                        row(entry)
                    }
                }
                if !archived.isEmpty {
                    Section("归档(数据保留)") {
                        ForEach(archived) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 560, minHeight: 440)
        .sheet(isPresented: $showNew) {
            NewProjectView(model: model) { refresh() }
        }
        .sheet(item: $versionsEntry) { entry in
            VersionsView(model: model, entry: entry)
        }
        .onAppear(perform: refresh)
    }

    private func row(_ entry: VaultEntry) -> some View {
        let isCurrent = model.vaultEntry?.id == entry.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.body.weight(isCurrent ? .semibold : .regular))
                    if isCurrent { Text("当前").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.accentColor.opacity(0.2))) }
                }
                Text(dateText(entry.updatedAt)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("打开") { model.openVaultEntry(entry) }
                .buttonStyle(.borderedProminent)
                .disabled(entry.archived)
            Button("版本…") { versionsEntry = entry }
                .buttonStyle(.bordered)
            Button(entry.archived ? "恢复" : "归档") {
                try? model.vault.setArchived(id: entry.id, archived: !entry.archived)
                refresh()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func dateText(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func refresh() {
        entries = (try? model.vault.library()) ?? []
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            model.importFileToVault(url: url)
            refresh()
        }
    }
}

// MARK: - 新建

struct NewProjectView: View {
    @ObservedObject var model: PlayerModel
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "未命名作品"
    @State private var bpm: Double = 90
    @State private var key = "A minor"
    @State private var bars: Double = 16
    @State private var style = ""

    private let keys = ["A minor", "C major", "D minor", "E minor", "G major", "F major"]
    private let barOptions: [Double] = [4, 8, 16, 32, 64]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建工程").font(.title3.bold())
            HStack {
                Text("名称")
                TextField("名称", text: $name).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("速度 \(Int(bpm)) BPM")
                Slider(value: $bpm, in: 40...200, step: 1)
            }
            HStack {
                Text("调性")
                Picker("", selection: $key) { ForEach(keys, id: \.self) { Text($0) } }
                    .labelsHidden().frame(width: 140)
                Spacer()
                Text("长度")
                Picker("", selection: $bars) { ForEach(barOptions, id: \.self) { Text("\(Int($0)) 小节") } }
                    .labelsHidden().frame(width: 120)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("起点").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $style) {
                    Text("空白工程").tag("")
                    ForEach(Tables.shared.styles, id: \.id) { s in
                        Text("\(s.icon) \(s.name)(\(Int(s.bpm)) BPM · \(s.desc))").tag(s.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("创建并打开") {
                    do {
                        if style.isEmpty {
                            let entry = try model.vault.create(name: name, bpm: bpm, key: key, bars: bars)
                            model.openVaultEntry(entry)
                        } else {
                            // 四风格起点 = 本机灵感引擎模板(与 Web 版一致,不是模型调用)
                            let project = try generateProject(GenerateOptions(
                                style: style, key: key, bars: bars,
                                seed: Int.random(in: 1...2_000_000_000)
                            ))
                            let entry = try model.vault.importProject(project, name: name.isEmpty ? nil : name)
                            model.openVaultEntry(entry)
                        }
                        onDone()
                        dismiss()
                    } catch {
                        model.error = "\(error)"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 430)
    }
}

// MARK: - 版本浏览

struct VersionsView: View {
    @ObservedObject var model: PlayerModel
    let entry: VaultEntry
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [VaultVersion] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("版本 · \(entry.name)").font(.title3.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(12)
            if versions.isEmpty {
                Spacer()
                Text("还没有保存点。播放器会每分钟自动留一个版本;也可在工具栏点「存版本」。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 380)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                List(versions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.label.isEmpty ? "自动保存" : version.label).font(.body)
                            Text("\(dateText(version.createdAt)) · \(version.reason) · \(version.size / 1024) KB")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") {
                            model.restoreVersion(entry: entry, version: version)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 440, minHeight: 360)
        .onAppear {
            versions = (try? model.vault.versions(entry.id)) ?? []
        }
    }

    private func dateText(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
#endif
