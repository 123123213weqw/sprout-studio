// 钢琴卷帘(只读):调性音符按音高铺开,鼓件走底部三条轨,
// 播放头 30fps 跟随,点击任意位置 seek。数据来自 playbackPlan——
// 画出来的事件就是调度给音频引擎的事件(含 swing/人性化偏移/静音音块过滤)。

#if canImport(AppKit)
import SwiftUI
import SproutKit
import SproutAudio

struct RollEvent {
    let beat: Double
    let duration: Double
    let pitch: Double
    let velocity: Double
    let colorHex: String
    let instrument: String
    let kind: String
}

struct RollView: View {
    @ObservedObject var model: PlayerModel
    var pxPerBeat: CGFloat = 26
    @State private var anchorBeat: Double = -1

    private var tonalEvents: [RollEvent] { model.rollEvents.filter { $0.kind != "drum" } }
    private var drumEvents: [RollEvent] { model.rollEvents.filter { $0.kind == "drum" } }

    private var pitchRange: (min: Double, max: Double) {
        let pitches = tonalEvents.map(\.pitch)
        let lo = pitches.min() ?? 48
        let hi = pitches.max() ?? 72
        let pad = max(2, (hi - lo) / 6)
        return (lo - pad, hi + pad)
    }

    var body: some View {
        let rollHeight: CGFloat = 300
        let drumHeight: CGFloat = CGFloat(drumLanes.count) * 22
        let contentWidth = CGFloat(model.totalBeats) * pxPerBeat
        let range = pitchRange

        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            noteCanvas(range: range, height: rollHeight)
                                .frame(width: contentWidth, height: rollHeight)
                            drumCanvas(height: drumHeight)
                                .frame(width: contentWidth, height: drumHeight)
                        }
                        // 播放头:随内容坐标移动
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                            .id("playhead")
                            .offset(x: CGFloat(model.beat) * pxPerBeat)
                    }
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .onChange(of: model.beat) { beat in
                    let visible = Double(geo.size.width / pxPerBeat)
                    if anchorBeat < 0 { anchorBeat = max(0, beat - visible * 0.3) }
                    if beat > anchorBeat + visible * 0.75 {
                        anchorBeat = beat - visible * 0.3
                        withAnimation(.linear(duration: 0.2)) { proxy.scrollTo("playhead", anchor: UnitPoint(x: 0.3, y: 0)) }
                    } else if beat < anchorBeat {
                        anchorBeat = max(0, beat - visible * 0.3)
                        withAnimation(.linear(duration: 0.2)) { proxy.scrollTo("playhead", anchor: UnitPoint(x: 0.3, y: 0)) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            let beat = Double(location.x / pxPerBeat)
            model.seek(to: beat)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var drumLanes: [String] {
        var order: [String] = []
        for event in drumEvents where !order.contains(event.instrument) {
            order.append(event.instrument)
        }
        return order.isEmpty ? ["kick", "snare", "hat"] : order
    }

    private func noteCanvas(range: (min: Double, max: Double), height: CGFloat) -> some View {
        Canvas { context, size in
            let span = max(1, range.max - range.min)
            let beatW = pxPerBeat
            // 网格:拍细线,小节粗线 + 小节号
            for bar in 0...(Int(model.totalBeats / 4)) {
                let x = CGFloat(bar * 4) * beatW
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.25)), lineWidth: bar % 4 == 0 ? 0 : 1)
                if bar % 4 == 0 {
                    context.draw(Text("\(bar)").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: x + 10, y: 8))
                }
            }
            // 音符
            let rowH = size.height / CGFloat(span)
            let noteH = max(2.5, min(6, rowH * 0.7))
            for event in tonalEvents {
                let y = size.height - CGFloat(event.pitch - range.min) / CGFloat(span) * size.height
                let rect = CGRect(
                    x: CGFloat(event.beat) * beatW + 0.6,
                    y: y - noteH / 2,
                    width: max(2.4, CGFloat(event.duration) * beatW - 1.2),
                    height: noteH
                )
                let opacity = 0.35 + 0.65 * (event.velocity / 127)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color(event.colorHex).opacity(opacity)))
            }
        }
    }

    private func drumCanvas(height: CGFloat) -> some View {
        Canvas { context, size in
            let lanes = drumLanes
            let laneH = size.height / CGFloat(max(1, lanes.count))
            for bar in 0...(Int(model.totalBeats / 4)) where bar % 4 == 0 {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(bar * 4) * pxPerBeat, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(bar * 4) * pxPerBeat, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.25)), lineWidth: 1)
            }
            for (i, lane) in lanes.enumerated() {
                let y0 = CGFloat(i) * laneH
                context.draw(Text(lane.uppercased()).font(.system(size: 8)).foregroundColor(.secondary),
                             at: CGPoint(x: 22, y: y0 + laneH / 2))
            }
            for event in drumEvents {
                guard let lane = lanes.firstIndex(of: event.instrument) else { continue }
                let y0 = CGFloat(lane) * laneH
                let rect = CGRect(
                    x: CGFloat(event.beat) * pxPerBeat + 0.6,
                    y: y0 + 3,
                    width: max(2.4, CGFloat(event.duration) * pxPerBeat - 1.2),
                    height: laneH - 6
                )
                let opacity = 0.35 + 0.65 * (event.velocity / 127)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color(event.colorHex).opacity(opacity)))
            }
        }
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: NSColor(hex: hex) ?? .gray)
    }
}
#endif
