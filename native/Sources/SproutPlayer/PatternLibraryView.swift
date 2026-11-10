// Pattern 库:浏览工程内共享乐句,放置到轨道末尾,改名/独立化全部/删除,
// 导入导出 .sprout-patterns(格式与 Web 版互通)。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit

struct PatternLibraryView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var importMessage: String?

    private var patterns: [JSONObject] {
        jarrPublic(model.project?["patterns"]).compactMap { $0.asObject }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共享 Pattern 库(\(patterns.count))").font(.title3.bold())
                Spacer()
                Button("导入 .sprout-patterns") { importPatterns() }
                Button("导出全部") { exportPatterns() }
                Button("关闭") { dismiss() }
            }
            .padding(12)
            Divider()
            if patterns.isEmpty {
                Spacer()
                Text("还没有共享乐句。在时间线里右键音块 →「存为共享 Pattern」,之后所有实例会一起更新。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: 420).multilineTextAlignment(.center)
                Spacer()
            } else {
                List(0..<patterns.count, id: \.self) { index in
                    row(patterns[index])
                }
                .listStyle(.inset)
            }
            if let message = importMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func row(_ pattern: JSONObject) -> some View {
        let patternId = pattern["id"]?.asString ?? ""
        let instances = model.patternInstanceCount(patternId)
        let noteCount = jarrPublic(pattern["notes"]).count
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern["name"]?.asString ?? "未命名乐句").font(.body)
                Text("\(pattern["instrument"]?.asString ?? "") · \(jnum(pattern, "length", 4)) 拍 · \(noteCount) 音符 · \(instances) 个实例")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("放置到…") {
                ForEach(Array(model.tracks.enumerated()), id: \.offset) { _, track in
                    Button(track["name"]?.asString ?? "") {
                        model.placePatternAtEnd(patternId: patternId, trackId: track["id"]?.asString ?? "")
                    }
                }
            }
            .fixedSize()
            Button("改名") {
                let alert = NSAlert()
                alert.messageText = "重命名 Pattern"
                alert.informativeText = "所有共享实例会一起更新。"
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
                input.stringValue = pattern["name"]?.asString ?? ""
                alert.accessoryView = input
                alert.addButton(withTitle: "确定")
                alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn {
                    model.renamePattern(patternId: patternId, name: input.stringValue)
                }
            }
            Button("删除") {
                model.deletePattern(patternId: patternId)
            }
            .tint(.red)
        }
        .padding(.vertical, 2)
    }

    private func importPatterns() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            let message = model.importPatternFile(url: url)
            importMessage = message
        }
    }

    private func exportPatterns() {
        guard let patterns = model.project?["patterns"] else {
            importMessage = "没有可导出的 Pattern"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "patterns.sprout-patterns"
        panel.begin { _ in
            guard let url = panel.url else { return }
            var wrapper = JSONObject()
            wrapper["format"] = .string("sprout-pattern-library")
            wrapper["version"] = .number(1)
            wrapper["patterns"] = patterns
            try? jsStringify(.object(wrapper)).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
