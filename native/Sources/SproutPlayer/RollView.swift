// 钢琴卷帘(可编辑):单击选中/定位,双击空处新建,拖拽移动,右缘拉伸,
// Delete 删除,1/16 网格吸附,撤销走整工程快照。
// 事件与音频调度同源(playbackPlan)——画的就是播的;编辑后经 validateProject
// 采纳并热重启播放,共享 Pattern 的音符被改动时会按非严格语义自动独立化。

#if canImport(AppKit)
import SwiftUI
import SproutKit
import SproutAudio

struct RollEvent {
    let noteId: String
    let trackId: String
    let beat: Double
    let duration: Double
    let pitch: Double
    let velocity: Double
    let colorHex: String
    let instrument: String
    let kind: String
}

private let grid = 0.25 // 1/16 吸附

private func snap(_ beat: Double) -> Double {
    (beat / grid).rounded() * grid
}

struct RollView: View {
    @ObservedObject var model: PlayerModel
    var pxPerBeat: CGFloat = 26
    @State private var anchorBeat: Double = -1

    // 编辑状态
    private enum DragMode { case move, resize }
    private struct DragContext {
        let event: RollEvent
        let mode: DragMode
        let grabOffset: Double // 按下点相对音符起点的拍数
        var beat: Double
        var pitch: Double
        var duration: Double
    }
    @State private var drag: DragContext?

    private var tonalEvents: [RollEvent] { model.rollEvents.filter { $0.kind != "drum" } }
    private var drumEvents: [RollEvent] { model.rollEvents.filter { $0.kind == "drum" } }

    private var pitchRange: (min: Double, max: Double) {
        let pitches = tonalEvents.map(\.pitch)
        let lo = pitches.min() ?? 48
        let hi = pitches.max() ?? 72
        let pad = max(2, (hi - lo) / 6)
        return (lo - pad, hi + pad)
    }

    private var tonalHeight: CGFloat { 300 }
    private var drumLanes: [String] {
        var order: [String] = []
        for event in drumEvents where !order.contains(event.instrument) {
            order.append(event.instrument)
        }
        return order.isEmpty ? ["kick", "snare", "hat"] : order
    }
    private var drumHeight: CGFloat { CGFloat(drumLanes.count) * 22 }

    var body: some View {
        let contentWidth = CGFloat(model.totalBeats) * pxPerBeat
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            noteCanvas.frame(width: contentWidth, height: tonalHeight)
                            drumCanvas.frame(width: contentWidth, height: drumHeight)
                        }
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                            .id("playhead")
                            .offset(x: CGFloat(model.beat) * pxPerBeat)
                    }
                    .frame(minHeight: geo.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .coordinateSpace(name: "roll")
                    .onTapGesture(count: 2, coordinateSpace: .named("roll")) { loc in
                        handleDoubleTap(at: loc)
                    }
                    .onTapGesture(coordinateSpace: .named("roll")) { loc in
                        handleSingleTap(at: loc)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named("roll"))
                            .onChanged { value in handleDragChange(value, at: value.startLocation) }
                            .onEnded { _ in commitDrag() }
                    )
                }
                .onChange(of: model.beat) { beat in
                    let visible = Double(geo.size.width / pxPerBeat)
                    if anchorBeat < 0 { anchorBeat = max(0, beat - visible * 0.3) }
                    if beat > anchorBeat + visible * 0.75 || beat < anchorBeat {
                        anchorBeat = max(0, beat - visible * 0.3)
                        withAnimation(.linear(duration: 0.2)) { proxy.scrollTo("playhead", anchor: UnitPoint(x: 0.3, y: 0)) }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 命中测试

    private func pitchAt(y: CGFloat) -> Double {
        let range = pitchRange
        let span = max(1, range.max - range.min)
        let value = range.max - Double(y / tonalHeight) * span
        return min(108, max(24, value.rounded()))
    }

    private func lanePitch(at point: CGPoint) -> (instrument: String, pitch: Double)? {
        let y = point.y - tonalHeight
        guard y >= 0, !drumLanes.isEmpty else { return nil }
        let index = min(drumLanes.count - 1, max(0, Int(y / 22)))
        let instrument = drumLanes[index]
        let pitch = ["kick": 36.0, "snare": 38.0, "hat": 42.0][instrument] ?? 36.0
        return (instrument, pitch)
    }

    /// 返回命中的音符与是否落在右缘(拉伸柄)
    private func hitTest(_ point: CGPoint) -> (event: RollEvent, resize: Bool)? {
        let beat = Double(point.x / pxPerBeat)
        if point.y > tonalHeight, let lane = lanePitch(at: point) {
            let candidates = drumEvents.filter { $0.instrument == lane.instrument }
            for event in candidates where beat >= event.beat - 0.1 && beat <= event.beat + event.duration + 0.1 {
                let rightEdge = event.beat + event.duration
                return (event, beat > rightEdge - max(0.12, 6.0 / Double(pxPerBeat)))
            }
            return nil
        }
        guard point.y >= 0, point.y <= tonalHeight else { return nil }
        let pitch = pitchAt(y: point.y)
        for event in tonalEvents where event.pitch == pitch
            && beat >= event.beat - 0.1 && beat <= event.beat + event.duration + 0.1 {
            let rightEdge = event.beat + event.duration
            return (event, beat > rightEdge - max(0.12, 6.0 / Double(pxPerBeat)))
        }
        return nil
    }

    // MARK: - 交互

    private func handleSingleTap(at point: CGPoint) {
        if let hit = hitTest(point) {
            model.selectedNoteId = hit.event.noteId
        } else {
            model.selectedNoteId = nil
            model.seek(to: Double(point.x / pxPerBeat))
        }
    }

    private func handleDoubleTap(at point: CGPoint) {
        guard hitTest(point) == nil else { return }
        let beat = min(max(0, snap(Double(point.x / pxPerBeat))), model.totalBeats - 0.28)
        if point.y > tonalHeight, let lane = lanePitch(at: point) {
            guard let track = model.tracks.first(where: { $0["instrument"]?.asString == lane.instrument }) else { return }
            model.createNote(trackId: track["id"]?.asString ?? "", beat: beat, pitch: lane.pitch, isDrum: true)
        } else if point.y >= 0 {
            guard let track = model.tracks.first(where: { ($0["kind"]?.asString ?? "tonal") != "drum" }) else { return }
            model.createNote(trackId: track["id"]?.asString ?? "", beat: beat, pitch: pitchAt(y: point.y), isDrum: false)
        }
    }

    private func handleDragChange(_ value: DragGesture.Value, at start: CGPoint) {
        if drag == nil {
            guard let hit = hitTest(start) else { return }
            let grabOffset = Double(start.x / pxPerBeat) - hit.event.beat
            drag = DragContext(
                event: hit.event,
                mode: hit.resize ? .resize : .move,
                grabOffset: max(0, grabOffset),
                beat: hit.event.beat,
                pitch: hit.event.pitch,
                duration: hit.event.duration
            )
            model.selectedNoteId = hit.event.noteId
        }
        guard var context = drag else { return }
        let beatAt = Double(value.location.x / pxPerBeat)
        switch context.mode {
        case .move:
            context.beat = min(max(0, snap(beatAt - context.grabOffset)), model.totalBeats - context.duration - 0.03)
            if context.event.kind == "drum" {
                if value.location.y > tonalHeight, let lane = lanePitch(at: value.location) {
                    context.pitch = lane.pitch
                }
            } else if value.location.y >= 0, value.location.y <= tonalHeight {
                context.pitch = pitchAt(y: value.location.y)
            }
        case .resize:
            context.duration = min(max(grid, snap(beatAt - context.event.beat)), model.totalBeats - context.event.beat)
        }
        drag = context
    }

    private func commitDrag() {
        guard let context = drag else { return }
        drag = nil
        switch context.mode {
        case .move:
            if context.beat != context.event.beat || context.pitch != context.event.pitch {
                model.updateNote(id: context.event.noteId, label: "移动音符", start: context.beat, pitch: context.pitch)
            }
        case .resize:
            if context.duration != context.event.duration {
                model.updateNote(id: context.event.noteId, label: "调整音长", duration: context.duration)
            }
        }
    }

    // MARK: - 绘制

    private var noteCanvas: some View {
        Canvas { context, size in
            let range = pitchRange
            let span = max(1, range.max - range.min)
            for bar in 0...(Int(model.totalBeats / 4)) {
                let x = CGFloat(bar * 4) * pxPerBeat
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(bar % 4 == 0 ? 0.35 : 0.18)), lineWidth: 1)
                if bar % 4 == 0 {
                    context.draw(Text("\(bar)").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: x + 10, y: 8))
                }
            }
            let rowH = size.height / CGFloat(span)
            let noteH = max(2.5, min(6, rowH * 0.7))
            for event in tonalEvents {
                var beat = event.beat
                var pitch = event.pitch
                var duration = event.duration
                var alpha = 0.35 + 0.65 * (event.velocity / 127)
                if let dragContext = drag, dragContext.event.noteId == event.noteId {
                    beat = dragContext.beat; pitch = dragContext.pitch; duration = dragContext.duration; alpha = 0.9
                }
                let y = size.height - CGFloat(pitch - range.min) / CGFloat(span) * size.height
                let rect = CGRect(
                    x: CGFloat(beat) * pxPerBeat + 0.6,
                    y: y - noteH / 2,
                    width: max(2.4, CGFloat(duration) * pxPerBeat - 1.2),
                    height: noteH
                )
                let selected = model.selectedNoteId == event.noteId
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                             with: .color(color(event.colorHex).opacity(alpha)))
                if selected {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 2.5),
                                   with: .color(.white.opacity(0.9)), lineWidth: 1.2)
                }
            }
        }
    }

    private var drumCanvas: some View {
        Canvas { context, size in
            let lanes = drumLanes
            let laneH = size.height / CGFloat(max(1, lanes.count))
            for bar in 0...(Int(model.totalBeats / 4)) where bar % 4 == 0 {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(bar * 4) * pxPerBeat, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(bar * 4) * pxPerBeat, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.35)), lineWidth: 1)
            }
            for (i, lane) in lanes.enumerated() {
                let y0 = CGFloat(i) * laneH
                context.draw(Text(lane.uppercased()).font(.system(size: 8)).foregroundColor(.secondary),
                             at: CGPoint(x: 22, y: y0 + laneH / 2))
            }
            for event in drumEvents {
                guard let lane = lanes.firstIndex(of: event.instrument) else { continue }
                var beat = event.beat
                var duration = event.duration
                var alpha = 0.35 + 0.65 * (event.velocity / 127)
                if let dragContext = drag, dragContext.event.noteId == event.noteId {
                    beat = dragContext.beat; duration = dragContext.duration; alpha = 0.9
                }
                let y0 = CGFloat(lane) * laneH
                let rect = CGRect(
                    x: CGFloat(beat) * pxPerBeat + 0.6,
                    y: y0 + 3,
                    width: max(2.4, CGFloat(duration) * pxPerBeat - 1.2),
                    height: laneH - 6
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color(event.colorHex).opacity(alpha)))
                if model.selectedNoteId == event.noteId {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 4),
                                   with: .color(.white.opacity(0.9)), lineWidth: 1.2)
                }
            }
        }
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: NSColor(hex: hex) ?? .gray)
    }
}
#endif
