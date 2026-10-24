import AppKit
import SwiftUI

@MainActor
final class PhysicsWorkspace: ObservableObject {
    static let shared = PhysicsWorkspace()
    @Published var code = ""
    @Published var structure = ""
    @Published var warnings: [String] = []
    @Published var error = ""
    @Published var busy = false
    @Published var mode: RecognitionMode = .equation
    @Published var image: NSImage?
    @Published var copied = false
    private var png: Data?
    @Published var recordID: UUID?
    private var task: Task<Void, Never>?
    var onPresent: (() -> Void)?
    @Published var notice = ""
    @Published var confidence: Double?
    @Published var isDemo = false

    func recognize(image: NSImage) {
        guard !busy else { return }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            error = "无法读取截图。"; show(); return
        }
        isDemo = false; notice = ""; confidence = nil
        self.image = image
        png = data
        mode = PhysicsSettings.shared.mode
        code = ""; structure = ""; warnings = []; error = ""
        recordID = nil
        retry()
    }

    func retry() {
        guard !busy, let png else { return }
        isDemo = false
        busy = true; error = ""; copied = false
        show()
        task = Task {
            defer { busy = false; task = nil }
            do {
                let configuration = try await PhysicsSettings.shared.configuration()
                let output: RecognitionOutput
                switch configuration.backend {
                case .mathpix:
                    let appID = configuration.appID
                    output = try await MathpixProvider(appID: appID, apiKey: configuration.apiKey, beforeSend: {
                        await MathpixCreditStore.shared.recordAttempt(appID: appID)
                    }, afterSend: {
                        await PhysicsSettings.shared.completedMathpixRequest(using: configuration)
                    }).recognize(png: png, mode: mode)
                case .openAI:
                    output = try await OpenAICompatibleVisionProvider(configuration: configuration).recognize(png: png, mode: mode)
                }
                try Task.checkCancellation()
                code = output.code; structure = output.structure; warnings = output.warnings; confidence = output.confidence
                do {
                    recordID = try RecognitionHistory.shared.add(mode: mode, configuration: configuration, output: output,
                                                                  png: PhysicsSettings.shared.persistImages ? png : nil)
                } catch { self.error = error.localizedDescription }
            } catch { self.error = error is CancellationError ? "已取消。" : error.localizedDescription }
        }
    }
    func showError(_ message: String) { error = message; show() }
    func showDemo() {
        guard !busy else { return }
        isDemo = true; confidence = nil
        mode = .equation; png = PhysicsSettingsView.testPNG(); image = png.flatMap(NSImage.init(data:))
        code = #"\begin{aligned} I_\eta(U)={}&\Theta(U-\eta)\left(\frac{1}{\eta}-\frac{1}{U}\right)\\&+\left(1-\frac{1}{\eta}\right)\Theta(U)-\ln\eta\,\delta(U).\end{aligned}"#
        structure = ""; warnings = []; notice = "离线界面演示 · 未调用 API"
        error = ""; recordID = nil; show()
    }
    func load(_ record: RecognitionRecord, present: Bool = true) {
        guard !busy else { return }
        isDemo = false; confidence = record.output.confidence; notice = ""
        mode = record.mode; code = record.output.code; structure = record.output.structure
        warnings = record.output.warnings; png = record.png; image = record.png.flatMap(NSImage.init(data:))
        recordID = record.id; copied = false; error = ""
        if present { show() }
    }
    func saveEdits() {
        guard let recordID else { return }
        do { try RecognitionHistory.shared.update(id: recordID, code: code); notice = "修改已保存。" }
        catch { self.error = error.localizedDescription }
    }
    func cancel() { task?.cancel() }
    func copy(_ format: LatexCopyFormat = .plain) {
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(mode == .equation ? format.wrap(code) : code, forType: .string)
    }
    func presentLocal(image: NSImage, code: String, notice: String) {
        self.image = image; self.code = code; self.notice = notice
        mode = .equation; structure = ""; warnings = []; error = ""; confidence = nil; recordID = nil; isDemo = false
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) { png = bitmap.representation(using: .png, properties: [:]) }
        show()
    }
    func clear() {
        guard !busy else { return }
        code = ""; structure = ""; warnings = []; error = ""; notice = ""; image = nil; png = nil
        recordID = nil; confidence = nil; isDemo = false; copied = false
    }
    func show() { onPresent?() }
}
