import SwiftUI
import AppKit

// A single compact popover mirrors the reference's toolbar / tabs / preview / copy rows.
enum SnipPanelPage { case ocr, data, original, settings, history }

@MainActor
final class SnipPanelState: ObservableObject {
    @Published var page: SnipPanelPage = .ocr
    @Published var pinned = false { didSet { pinChanged?(pinned) } }
    var capture: (() -> Void)?
    var importImage: (() -> Void)?
    var pasteImage: (() -> Void)?
    var pinChanged: ((Bool) -> Void)?
}


struct SnipPanelView: View {
    @ObservedObject var state: SnipPanelState
    @ObservedObject private var workspace = PhysicsWorkspace.shared
    @ObservedObject private var history = RecognitionHistory.shared
    @ObservedObject private var settings = PhysicsSettings.shared
    @ObservedObject private var usage = MathpixUsageStore.shared
    @ObservedObject private var credit = MathpixCreditStore.shared
    @State private var copiedRow: SnipCopyStyle?
    @State private var showOriginal = false
    @State private var previewScale = 1.0
    private let ink = Color(red: 0.46, green: 0.47, blue: 0.62)
    private let rule = Color(red: 0.87, green: 0.87, blue: 0.91)
    private let pale = Color(red: 0.975, green: 0.975, blue: 0.985)

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 35)
            Rectangle().fill(rule).frame(height: 1)
            if state.page == .settings || state.page == .history {
                HStack {
                    Button { state.page = .ocr } label: { Label("返回识别", systemImage: "chevron.left") }.buttonStyle(.plain)
                    Spacer(); Text(state.page == .settings ? "设置" : "历史记录").fontWeight(.medium); Spacer()
                    Text("ScreenScribe").foregroundStyle(ink)
                }.padding(.horizontal, 18).frame(height: 30).background(pale)
                if state.page == .settings { SettingsView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { RecognitionHistoryView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                tabs.frame(height: 25)
                Rectangle().fill(rule).frame(height: 1)
                if state.page == .data { dataPage }
                else {
                    previewHeader.frame(height: 31)
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                actionStrip.frame(height: 31)
                Rectangle().fill(rule).frame(height: 1)
                copyRows.padding(.horizontal, 24).padding(.vertical, 10).background(pale)
                footer.frame(height: 42)
            }
        }
        .frame(width: 716, height: 524)
        .background(.white)
        .foregroundStyle(Color(red: 0.24, green: 0.24, blue: 0.28))
        .font(.system(size: 12))
        .tint(ink)
        .preferredColorScheme(.light)
        .onChange(of: workspace.code) { _, _ in copiedRow = nil }
        .onChange(of: workspace.error) { _, _ in if !workspace.error.isEmpty { state.page = .data } }
        .task(id: settings.backend) { if !workspace.isDemo { await refreshUsage() } }
    }
    private var toolbar: some View {
        HStack(spacing: 16) {
            icon("viewfinder", "框选截图 · ⌘⇧L") { state.capture?() }.disabled(workspace.busy)
            icon("photo.badge.plus", "从本地图片识别") { state.importImage?() }.disabled(workspace.busy)
            icon("photo.on.rectangle", "粘贴截图 · ⌘⇧V") { state.pasteImage?() }.disabled(workspace.busy)
            Menu {
                Picker("识别类型", selection: $settings.mode) {
                    ForEach(RecognitionMode.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Picker("识别服务", selection: $settings.backend) {
                    ForEach(RecognitionBackend.allCases) { Text($0.title).tag($0) }
                }
            } label: { Image(systemName: settings.mode == .equation ? "function" : "point.3.connected.trianglepath.dotted").font(.system(size: 18)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("识别类型和 API 服务")
            icon("keyboard", "快捷键设置") { state.page = .settings }
            icon("list.bullet", "历史记录") { state.page = .history }
            Rectangle().fill(rule).frame(width: 1, height: 22)
            HStack(spacing: 13) {
                icon("backward.end", "第一条记录") { if let last = history.records.last { workspace.load(last) } }.disabled(history.records.isEmpty || workspace.busy)
                icon("chevron.left", "上一条记录") { navigate(1) }.disabled(!canNavigate(1) || workspace.busy)
                Text(counter).font(.system(size: 13)).monospacedDigit().frame(minWidth: 62)
                icon("chevron.right", "下一条记录") { navigate(-1) }.disabled(!canNavigate(-1) || workspace.busy)
                icon("forward.end", "最新记录") { if let first = history.records.first { workspace.load(first) } }.disabled(history.records.isEmpty || workspace.busy)
            }
            Spacer(minLength: 0)
            icon("trash", "删除当前记录 / 清除当前结果") { deleteCurrent() }.disabled(workspace.busy)
            icon(state.pinned ? "pin.fill" : "pin", "固定此面板") { state.pinned.toggle() }
            icon("gearshape", "设置") { state.page = state.page == .settings ? .ocr : .settings }
        }.padding(.horizontal, 20).foregroundStyle(ink)
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            tab("OCR", .ocr); tab("Data", .data); tab("Original", .original)
            Spacer()
            if settings.backend == .mathpix && !workspace.isDemo {
                Menu {
                    Text(credit.statusText)
                    Text(credit.detailText)
                    Button("更新账单余额快照") { state.page = .settings }
                    Divider()
                    Text(usage.detailText)
                    Button("刷新用量") { Task { await refreshUsage() } }.disabled(usage.refreshing)
                    Button("设置图片月上限") { state.page = .settings }
                } label: {
                    Text(credit.remainingImages == nil ? usage.statusText : "\(credit.statusText) · \(usage.statusText)")
                        .font(.system(size: 10)).monospacedDigit().lineLimit(1)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(credit.detailText + "\n" + usage.detailText)
                    .padding(.trailing, 12)
            }
            Text(workspace.isDemo ? "离线演示" : settings.backend.title).font(.system(size: 10)).foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.50))
            Text(settings.mode == .equation ? "Equation" : "Feynman · 实验性")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color(red: 0.16, green: 0.40, blue: 0.41), in: RoundedRectangle(cornerRadius: 3))
        }.padding(.horizontal, 7).padding(.trailing, 12)
    }
    private func tab(_ title: String, _ page: SnipPanelPage) -> some View {
        Button { state.page = page } label: {
            Text(title).frame(width: 68, height: 23)
                .background(state.page == page ? Color.white : Color(red: 0.95, green: 0.95, blue: 0.965))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5).stroke(rule, lineWidth: 0.6))
        }.buttonStyle(.plain)
    }
    private var previewHeader: some View {
        HStack {
            Button { showOriginal.toggle() } label: {
                HStack(spacing: 6) { Text(showOriginal ? "Hide Original" : "Show Original"); Image(systemName: "chevron.down").font(.system(size: 10)) }
            }.buttonStyle(.plain).disabled(workspace.image == nil)
            Spacer()
            if workspace.busy {
                ProgressView().controlSize(.mini); Text("识别中…").foregroundStyle(ink)
                Button("取消") { workspace.cancel() }.buttonStyle(.plain)
            } else if !workspace.notice.isEmpty { Text(workspace.notice).font(.system(size: 10)).foregroundStyle(ink).lineLimit(1) }
            icon("arrow.clockwise", "重新识别（当前设置）") { workspace.retry() }.disabled(workspace.image == nil || workspace.busy)
        }.padding(.horizontal, 18)
    }
    @ViewBuilder private var preview: some View {
        if state.page == .original || showOriginal {
            if let image = workspace.image { Image(nsImage: image).resizable().scaledToFit().padding(14) }
            else { empty("此记录没有保存原图", symbol: "photo") }
        } else if workspace.mode == .feynman && !workspace.code.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("图结构").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                ScrollView { Text(workspace.structure).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text("TikZ 源码可在 Data 中编辑；尚未自动编译。").font(.system(size: 10)).foregroundStyle(ink)
            }.padding(20)
        } else { LocalMathPreview(code: workspace.code, scale: previewScale) }
    }
    private var dataPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(workspace.mode == .equation ? "LaTeX 源码" : "TikZ 源码").fontWeight(.medium)
                Spacer()
                Button("保存修改") { workspace.saveEdits() }.disabled(workspace.recordID == nil || workspace.busy)
            }
            if !workspace.error.isEmpty { Text(workspace.error).foregroundStyle(.red).textSelection(.enabled).font(.system(size: 11)) }
            TextEditor(text: $workspace.code).font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden).disabled(workspace.busy)
            if !workspace.warnings.isEmpty {
                ScrollView { Text(workspace.warnings.joined(separator: "\n")).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 55)
            }
        }.padding(15).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var actionStrip: some View {
        HStack(spacing: 20) {
            Button { workspace.copy() } label: { Label("Copy LaTeX", systemImage: "doc.on.clipboard") }.disabled(workspace.code.isEmpty)
                .contextMenu {
                    ForEach(LatexCopyFormat.allCases) { format in Button("复制 " + format.rawValue) { workspace.copy(format) } }
                }
            Button { state.page = .data } label: { Label("Edit Source", systemImage: "square.and.pencil") }.disabled(workspace.code.isEmpty)
            Spacer()
            Button { copyPNG() } label: { Label("Copy PNG", systemImage: "doc.on.doc") }.disabled(workspace.code.isEmpty && workspace.image == nil)
            Button { state.page = .original } label: { Label("Original", systemImage: "photo") }.disabled(workspace.image == nil)
            icon("slider.horizontal.3", "查看识别歧义和源码") { state.page = .data }
        }.buttonStyle(.plain).padding(.horizontal, 18).font(.system(size: 11))
    }
    private var copyRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(SnipCopyStyle.allCases.enumerated()), id: \.element.id) { index, style in
                if index > 0 { Rectangle().fill(rule).frame(height: 0.7) }
                HStack(spacing: 8) {
                    Text(copyRowPreview(style))
                        .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                    rowIcon(copiedRow == style ? "checkmark" : "doc.on.clipboard", "复制 " + style.rawValue) {
                        NSPasteboard.general.clearContents()
                        if NSPasteboard.general.setString(workspace.mode == .feynman ? workspace.code : style.source(workspace.code), forType: .string) { copiedRow = style }
                    }
                    rowIcon("square.and.pencil", "编辑源码") { state.page = .data }
                    rowIcon("magnifyingglass", "放大公式预览") { state.page = .ocr; showOriginal = false; previewScale = previewScale == 1 ? 1.35 : 1 }
                }.frame(height: 32).padding(.trailing, 7).disabled(workspace.code.isEmpty || workspace.busy)
            }
        }.background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.78, green: 0.78, blue: 0.81), lineWidth: 0.8))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workspace.confidence == nil ? "Confidence · 未提供" : "Confidence · \(Int((workspace.confidence ?? 0) * 100))%")
                Spacer()
                if copiedRow != nil || workspace.copied { Text("已复制 ✓") }
                else if !workspace.error.isEmpty { Button("查看错误") { state.page = .data }.foregroundStyle(.red).buttonStyle(.plain) }
                else if !workspace.warnings.isEmpty { Button("\(workspace.warnings.count) 项核查提示") { state.page = .data }.buttonStyle(.plain) }
                else { Text("仅处理所选区域 · 本地历史") }
            }.font(.system(size: 10)).foregroundStyle(ink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.92, green: 0.93, blue: 0.95))
                    if let confidence = workspace.confidence { Capsule().fill(Color(red: 0.23, green: 0.74, blue: 0.36)).frame(width: geometry.size.width * min(1,max(0,confidence))) }
                }
            }.frame(height: 7)
        }.padding(.horizontal, 20).padding(.bottom, 5)
    }
    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16)).frame(minWidth: 16, minHeight: 22) }
            .buttonStyle(.plain).foregroundStyle(ink).help(help).accessibilityLabel(help)
    }
    private func refreshUsage() async {
        guard settings.backend == .mathpix else { return }
        if let configuration = try? await settings.configuration() { settings.refreshMathpixUsage(using: configuration) }
    }
    private func copyRowPreview(_ style: SnipCopyStyle) -> String {
        guard !workspace.code.isEmpty else { return style.rawValue }
        let body = workspace.code.replacingOccurrences(of: "\n", with: " ")
        switch style {
        case .plain: return body
        case .inline: return "$\(body)$"
        case .display: return "$$\(body)$$"
        case .equation: return "\\begin{equation}\(body)\\end{equation}"
        }
    }
    private func rowIcon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 17)).frame(width: 27, height: 29).foregroundStyle(ink)
            .background(.white, in: RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(rule, lineWidth: 1)) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
    private func empty(_ title: String, symbol: String) -> some View {
        VStack(spacing: 10) { Image(systemName: symbol).font(.system(size: 25)); Text(title) }.foregroundStyle(ink.opacity(0.7)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var recordIndex: Int? { history.records.firstIndex { $0.id == workspace.recordID } }
    private var counter: String {
        if workspace.isDemo { return "示例" }
        guard let index = recordIndex else { return "\(history.records.count)/\(history.records.count)" }
        return "\(history.records.count - index)/\(history.records.count)"
    }
    private func canNavigate(_ delta: Int) -> Bool { guard let index = recordIndex else { return !history.records.isEmpty }; return history.records.indices.contains(index + delta) }
    private func navigate(_ delta: Int) { let index = recordIndex.map { $0 + delta } ?? 0; if history.records.indices.contains(index) { workspace.load(history.records[index]) } }
    private func deleteCurrent() {
        do { if let id = workspace.recordID { try history.remove(id: id) }; workspace.clear() }
        catch { workspace.error = error.localizedDescription; state.page = .data }
    }
    private func copyPNG() {
        Task { @MainActor in
            if state.page == .data { state.page = .ocr }
            let image = (state.page == .original || showOriginal || workspace.code.isEmpty || workspace.mode == .feynman) ? workspace.image : await MathPreviewBridge.shared.image()
            guard let image else { workspace.notice = "无法复制图片，请切换 Original 后重试。"; return }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { return }
            NSPasteboard.general.clearContents(); workspace.copied = NSPasteboard.general.setData(png, forType: .png)
        }
    }
}
