// 时间线:每轨一行音块,与卷帘同坐标滚动(嵌在 RollView 的滚动内容里)。
// 点选音块;右键:复制/分割/拉长/缩短/静音/删除/存为 Pattern/独立化。
// 所有操作走 ClipOps(已与 JS 对拍),经 applyEdit 可撤销。

#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit

struct TimelineView: View {
    @ObservedObject var model: PlayerModel
    var pxPerBeat: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.tracks.enumerated()), id: \.offset) { index, track in
                lane(track: track, index: index)
            }
        }
    }

    private func lane(track: JSONObject, index: Int) -> some View {
        let trackId = track["id"]?.asString ?? ""
        let color = Color(nsColor: NSColor(hex: track["color"]?.asString ?? "#888888") ?? .gray)
        return ZStack(alignment: .leading) {
            Rectangle().fill(Color(nsColor: .controlBackgroundColor)).frame(height: 26)
            ForEach(Array(jarrPublic(track["clips"]).enumerated()), id: \.offset) { _, cv in
                if let clip = cv.asObject {
                    clipBlock(clip, trackId: trackId, color: color, muted: clip["muted"]?.asBool == true, linked: clip.has("patternId"))
                }
            }
        }
        .frame(height: 26)
        .overlay(alignment: .leading) {
            Text(track["name"]?.asString ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .padding(.horizontal, 3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 2))
                .offset(x: 2, y: 0)
                .allowsHitTesting(false)
        }
    }

    private func transformDialog(_ clip: JSONObject) {
        let alert = NSAlert()
        alert.messageText = "乐句变换(整块应用,可撤销)"
        let grid = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        grid.orientation = .vertical
        grid.spacing = 6
        let ratio = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        ratio.addItems(withTitles: ["原速", "减半", "加倍"])
        let transpose = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        transpose.addItems(withTitles: ["不移调", "+12 半音", "-12 半音", "+7(吸附 A 小调)", "-5(吸附 A 小调)"])
        let timing = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        timing.addItems(withTitles: ["微偏移跟随", "保持", "清除"])
        let reverse = NSButton(checkboxWithTitle: "倒序", target: nil, action: nil)
        let extend = NSButton(checkboxWithTitle: "超出工程时空白延长", target: nil, action: nil)
        for row in [[ratio, transpose], [timing, reverse], [extend]] {
            let h = NSStackView(views: row)
            h.orientation = .horizontal
            h.distribution = .fillEqually
            grid.addArrangedSubview(h)
        }
        alert.accessoryView = grid
        alert.addButton(withTitle: "变换")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var controls = JSONObject()
        controls["ratio"] = .number([1, 0.5, 2][ratio.indexOfSelectedItem])
        let tp = transpose.indexOfSelectedItem
        controls["transpose"] = .number([0, 12, -12, 7, -5][tp])
        if tp >= 3 { controls["scale"] = .string("A minor") }
        controls["timing"] = .string(["follow", "keep", "clear"][timing.indexOfSelectedItem])
        controls["reverse"] = .bool(reverse.state == .on)
        controls["extend"] = .bool(extend.state == .on)
        let trackId = model.selectedClipTrackId ?? ""
        let clipId = clip["id"]?.asString ?? ""
        model.clipOp("乐句变换") { p in
            try planPhraseTransform(p, trackId: trackId, clipId: clipId, controls: controls).project
        }
    }

    private func clipBlock(_ clip: JSONObject, trackId: String, color: Color, muted: Bool, linked: Bool) -> some View {
        let clipId = clip["id"]?.asString ?? ""
        let start = jnum(clip, "start")
        let length = jnum(clip, "length", 4)
        let selected = model.selectedClipId == clipId
        return Group {
            Rectangle()
                .fill(color.opacity(muted ? 0.25 : 0.65))
                .overlay(
                    Rectangle().strokeBorder(
                        selected ? Color.white : Color.black.opacity(0.25),
                        lineWidth: selected ? 1.5 : 0.5
                    )
                )
                .overlay(alignment: .topLeading) {
                    if linked {
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 4, height: 4).padding(2)
                    }
                }
        }
        .frame(width: max(6, CGFloat(length) * pxPerBeat - 2), height: 22)
        .offset(x: CGFloat(start) * pxPerBeat + 1, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedClipId = clipId }
        .contextMenu {
            Button("复制一份") { model.clipOp("复制音块") { p in try moveClip(p, trackId: trackId, clipId: clipId, to: start, duplicate: true).project } }
            Button("向右复制 ×2") { model.clipOp("复制两份") { p in try repeatClip(p, trackId: trackId, clipId: clipId, count: 2).project } }
            Button("拉长 1 拍") { model.clipOp("拉长音块") { p in try resizeClip(p, trackId: trackId, clipId: clipId, to: length + 1) } }
            Button("缩短 1 拍") { model.clipOp("缩短音块") { p in try resizeClip(p, trackId: trackId, clipId: clipId, to: max(0.25, length - 1)) } }
            Button("从中间分割") { model.clipOp("分割音块") { p in try splitClip(p, trackId: trackId, clipId: clipId, at: start + min(2, length / 2)).project } }
            Button(muted ? "取消静音" : "静音音块") { model.clipOp("音块静音") { p in try updateClip(p, trackId: trackId, clipId: clipId, start: start, length: length, muted: !muted) } }
            Button("乐句变换…") { transformDialog(clip) }
            Divider()
            Button("存为共享 Pattern") { model.captureSelectedClipAsPattern(name: clip["name"]?.asString ?? "乐句") }
            if linked {
                Button("解除共享(保留音符)") { model.clipOp("独立化音块") { p in try detachPatternClip(p, trackId: trackId, clipId: clipId) } }
            }
            Divider()
            Button("删除音块", role: .destructive) { model.clipOp("删除音块") { p in try removeClip(p, trackId: trackId, clipId: clipId) } }
        }
    }
}
#endif
