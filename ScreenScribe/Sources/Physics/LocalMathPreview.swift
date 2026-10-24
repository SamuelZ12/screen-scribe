import SwiftUI
import WebKit

@MainActor
final class MathPreviewBridge {
    static let shared = MathPreviewBridge()
    weak var webView: WKWebView?
    var rendered = false
    func image() async -> NSImage? {
        for _ in 0..<30 {
            if rendered, let webView {
                _ = try? await webView.callAsyncJavaScript("await document.fonts.ready", arguments: [:], in: nil, contentWorld: .page)
                return try? await webView.takeSnapshot(configuration: nil)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }
}

struct LocalMathPreview: NSViewRepresentable {
    let code: String
    var scale: Double = 1
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        MathPreviewBridge.shared.webView = view
        MathPreviewBridge.shared.rendered = false
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("MathPreview"),
           FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) {
            view.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.code = code
        context.coordinator.scale = scale
        if context.coordinator.loaded { context.coordinator.render(view) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var code = ""
        var scale = 1.0
        var loaded = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; render(webView) }
        func render(_ view: WKWebView) {
            // Pass the source as an argument, never interpolate it into HTML or executable JS.
            let arguments: [String: Any] = ["source": code, "scale": scale]
            MathPreviewBridge.shared.rendered = false
            Task {
                _ = try? await view.callAsyncJavaScript("window.renderEquation(source, scale)", arguments: arguments, in: nil, contentWorld: .page)
                if MathPreviewBridge.shared.webView === view { MathPreviewBridge.shared.rendered = true }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
