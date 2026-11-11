// 循环区(练习范围)设置:起止拍滑杆,清空恢复整曲;卷帘播放头在其间循环。
#if canImport(AppKit)
import AppKit
import SwiftUI
import SproutKit

struct LoopRangeView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Double = 0
    @State private var end: Double = 16

    var body: some View {
        let total = model.totalBeats
        return VStack(alignment: .leading, spacing: 12) {
            Text("循环区(练习范围)").font(.title3.bold())
            if let range = model.loopRange {
                Text("当前:\(range.start) – \(range.end) 拍(共 \(String(format: "%.1f", range.end - range.start)) 拍)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("未设置:播放整曲循环。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("起点 \(Int(start))").font(.caption).frame(width: 70)
                Slider(value: $start, in: 0...max(1, total - 1), step: 1)
            }
            HStack {
                Text("终点 \(Int(end))").font(.caption).frame(width: 70)
                Slider(value: $end, in: 1...total, step: 1)
            }
            HStack {
                Button("清除循环区") { model.clearLoopRange(); dismiss() }
                Spacer()
                Button("取消") { dismiss() }
                Button("设置") {
                    model.setLoopRange(start: min(start, end - 0.25), end: max(end, start + 0.25))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            if let range = model.loopRange {
                start = range.start
                end = range.end
            } else {
                end = model.totalBeats
            }
        }
    }
}
#endif
