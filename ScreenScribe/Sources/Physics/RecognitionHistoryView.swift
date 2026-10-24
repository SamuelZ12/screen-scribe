import SwiftUI
import AppKit

struct RecognitionHistoryView: View {
    @ObservedObject private var history = RecognitionHistory.shared
    @ObservedObject private var workspace = PhysicsWorkspace.shared
    @State private var message = ""
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("最近识别 · \(history.records.count)/50").font(.title2.bold())
                Spacer()
                Button("移除全部原图") { perform { try history.removeImages() } }
                Button("清空历史", role: .destructive) { confirmClear = true }
            }
            Text("本地最多 50 条、约 25 MB 图文数据；可编辑结果需点击“保存修改”更新记录。").font(.caption).foregroundStyle(.secondary)
            if !history.error.isEmpty { Text(history.error).foregroundStyle(.red) }
            if !message.isEmpty { Text(message) }
            if history.records.isEmpty { ContentUnavailableView("暂无识别记录", systemImage: "clock") }
            List(history.records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.mode.title).font(.headline)
                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Spacer()
                        Button("查看 / 编辑") { workspace.load(record) }.disabled(workspace.busy)
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            message = NSPasteboard.general.setString(record.output.code, forType: .string) ? "已复制 ✓" : "复制失败"
                        }
                        Button("删除", role: .destructive) { perform { try history.remove(id: record.id) } }
                    }
                    Text("\(record.backend.title) · \(record.model) · \(record.png == nil ? "仅文本" : "含原图")").font(.caption)
                    Text(record.output.code.prefix(160)).font(.system(.caption, design: .monospaced)).lineLimit(2)
                }.padding(.vertical, 6)
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("清空所有识别记录及原图？", isPresented: $confirmClear) {
            Button("清空历史", role: .destructive) { perform { try history.clear() } }
        }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); message = "已完成。" } catch { message = error.localizedDescription }
    }
}

@MainActor
final class RecognitionHistoryWindow {
    static let shared = RecognitionHistoryWindow()
    func show() { (NSApp.delegate as? App)?.showHistory() }
}
