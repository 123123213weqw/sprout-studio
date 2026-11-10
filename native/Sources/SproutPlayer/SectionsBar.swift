// 段落条:工程的歌曲段落标签(前奏/主歌/副歌…),与时间线同坐标;
// 右键编辑/删除/生成过门;尾部菜单:骨架模板与新建段落。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit

struct SectionsBar: View {
    @ObservedObject var model: PlayerModel
    var pxPerBeat: CGFloat
    @State private var selectedSectionId: String?

    private let kindColors: [String: Color] = [
        "intro": .teal, "verse": .indigo, "chorus": .orange,
        "bridge": .purple, "outro": .gray, "custom": .accentColor
    ]

    var body: some View {
        let sections = jarrPublic(model.project?["sections"]).compactMap { $0.asObject }
        return ZStack(alignment: .leading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor)).frame(height: 20)
            ForEach(0..<sections.count, id: \.self) { index in
                block(sections[index])
            }
            if sections.isEmpty {
                Text("没有段落 · 用右侧「段落」菜单生成骨架")
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 20)
        .overlay(alignment: .trailing) {
            Menu {
                Button("骨架:主歌/副歌") { model.applySectionOp("套用主歌/副歌骨架") { p in try sectionTemplate(p, template: "verse-chorus") } }
                Button("骨架:前奏/主歌/副歌/尾奏") { model.applySectionOp("套用四段骨架") { p in try sectionTemplate(p, template: "four-parts") } }
                Divider()
                Button("新建段落(0 起,4 小节)…") { addSectionDialog() }
            } label: {
                Text("段落").font(.system(size: 9)).padding(.horizontal, 5)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 2)
        }
    }

    private func borderColor(_ selected: Bool) -> Color {
        selected ? Color.white : Color.black.opacity(0.15)
    }

    private func block(_ section: JSONObject) -> some View {
        let id = section["id"]?.asString ?? ""
        let kind = section["kind"]?.asString ?? "custom"
        let start = jnum(section, "start")
        let length = jnum(section, "length", 4)
        let selected: Bool = selectedSectionId == id
        let width: CGFloat = max(24, CGFloat(length) * pxPerBeat - 2)
        let fill = kindColors[kind]?.opacity(selected ? 0.55 : 0.35)
        return Text("\(section["name"]?.asString ?? "")")
            .font(.system(size: 9, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: width, height: 16, alignment: .center)
            .background(fill ?? Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(borderColor(selected), lineWidth: selected ? 1.2 : 0.5))
            .offset(x: CGFloat(start) * pxPerBeat + 1, y: 2)
            .help("\(section["name"]?.asString ?? "") · \(Int(length / 4)) 小节")
            .onTapGesture { selectedSectionId = id }
            .contextMenu {
                Button("编辑…") { editDialog(section) }
                Button("生成过门…") { fillDialog(section) }
                Divider()
                Button("删除段落", role: .destructive) {
                    model.applySectionOp("删除段落") { p in try deleteSection(p, id: id) }
                }
            }
    }

    private func textDialog(_ title: String, placeholder: String, initial: String, apply: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = placeholder
        input.stringValue = initial
        alert.accessoryView = input
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            apply(input.stringValue)
        }
    }

    private func addSectionDialog() {
        textDialog("新建段落", placeholder: "名称(0 起,4 小节)", initial: "副歌") { name in
            model.applySectionOp("新建段落") { p in
                try updateSection(p, name: name.isEmpty ? "自定义" : name, kind: "custom", start: 0, length: 16).project
            }
        }
    }

    private func editDialog(_ section: JSONObject) {
        let id = section["id"]?.asString ?? ""
        textDialog("重命名段落", placeholder: "名称", initial: section["name"]?.asString ?? "") { name in
            model.applySectionOp("重命名段落") { p in
                try updateSection(p, id: id, name: name.isEmpty ? "自定义" : name,
                                  kind: section["kind"]?.asString ?? "custom",
                                  start: jnum(section, "start"),
                                  length: jnum(section, "length", 4)).project
            }
        }
    }

    private func fillDialog(_ section: JSONObject) {
        let alert = NSAlert()
        alert.messageText = "生成过门(段落末尾鼓填充)"
        alert.informativeText = "在段落最后 1–2 小节的鼓轨写入填充,边缘长音自动切分保留。"
        let stylePop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        stylePop.addItems(withTitles: ["轻轻带过去(1 小节)", "逐渐加密(1 小节)", "留半拍呼吸(1 小节)", "逐渐加密(2 小节)"])
        alert.accessoryView = stylePop
        alert.addButton(withTitle: "生成")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let styleMap = [["gentle", "1"], ["rise", "1"], ["break", "1"], ["rise", "2"]][stylePop.indexOfSelectedItem]
        let sectionId = section["id"]?.asString ?? ""
        let drumIds = model.tracks.filter { $0["kind"]?.asString == "drum" }.map { $0["id"]?.asString ?? "" }
        guard !drumIds.isEmpty else {
            model.error = "请选择至少一条现有鼓轨，不得重复或选择旋律轨"
            return
        }
        model.applySectionOp("生成过门") { p in
            var controls = JSONObject()
            controls["style"] = .string(styleMap[0])
            controls["bars"] = .number(Double(styleMap[1]) ?? 1)
            controls["energy"] = .number(70)
            controls["seed"] = .number(Double(Int.random(in: 1...2_000_000)))
            controls["fillGaps"] = .bool(true)
            return try planSectionFill(p, sectionId: sectionId, trackIds: drumIds, controls: controls).project
        }
    }
}
#endif
