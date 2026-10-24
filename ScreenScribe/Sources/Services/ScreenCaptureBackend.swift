import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

enum ScreenCaptureBackend: String, Equatable, CustomStringConvertible {
    case legacyScreencaptureCLI
    case nativeRegionSelection

    var description: String {
        rawValue
    }
}

struct ScreenCaptureCLIArguments {
    static func selectionArguments(outputURL: URL) -> [String] {
        ["-i", "-s", "-x", "-t", "png", outputURL.path]
    }
}

struct ScreenCaptureStrategy {
    static func preferred(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> ScreenCaptureBackend {
        if version.majorVersion > 15 || (version.majorVersion == 15 && version.minorVersion >= 2) { return .nativeRegionSelection }
        return .legacyScreencaptureCLI
    }
}

struct ScreenCaptureCoordinates {
    static func quartzRect(fromAppKit rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

#if canImport(AppKit) && canImport(ScreenCaptureKit)
@MainActor
final class ScreenCaptureService {
    private let selector = ScreenRegionSelector()
    private let permissionCheck: () -> Bool
    private var selecting = false
    private(set) var lastError: String?
    init(permissionCheck: @escaping () -> Bool = CGPreflightScreenCaptureAccess) {
        self.permissionCheck = permissionCheck
    }

    static func activeBackend(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> ScreenCaptureBackend {
        ScreenCaptureStrategy.preferred(for: version)
    }

    func captureSelectionImage() async -> NSImage? {
        guard !selecting else { return nil }
        // The user explicitly requested no further permission prompts. Calling
        // capture APIs with an unconfirmed build can both prompt and return only
        // wallpaper. Never upload that partial result as a successful screenshot.
        guard permissionCheck() else {
            lastError = "系统尚未确认此应用的录屏授权。请在设置中点击“启用直接框选”。若 ScreenScribe 已开启，请移除旧记录，再添加“在 Finder 中定位此应用”显示的版本，并按系统提示重启。应用不会在后台反复申请。"
            return nil
        }
        selecting = true; lastError = nil
        // Hide all our document/result/settings windows before invoking Apple's selector.
        let visible = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
        visible.forEach { $0.orderOut(nil) }
        defer { selecting = false; visible.forEach { $0.orderFront(nil) } }
        try? await Task.sleep(nanoseconds: 200_000_000)
        switch Self.activeBackend() {
        case .legacyScreencaptureCLI:
            return await captureWithLegacyCLI()
        case .nativeRegionSelection:
            if #available(macOS 15.2, *) {
                return await captureWithNativeRegionSelection()
            }

            return await captureWithLegacyCLI()
        }
    }

    @available(macOS 15.2, *)
    private func captureWithNativeRegionSelection() async -> NSImage? {
        guard let rect = await selector.selectRegion() else {
            return nil
        }

        // Let the overlay disappear before ScreenCaptureKit samples the screen.
        try? await Task.sleep(nanoseconds: 75_000_000)

        do {
            let captureRect = ScreenCaptureCoordinates.quartzRect(fromAppKit: rect, primaryDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
            let image = try await captureImage(in: captureRect)
            return NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        } catch {
            lastError = "系统未能完成所选区域截图（ScreenCaptureKit）。这不是预检查结论；请核对当前运行版本与已授权应用的路径是否一致。"
            return nil
        }
    }

    private func captureWithLegacyCLI() async -> NSImage? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenscribe-\(UUID().uuidString)")
            .appendingPathExtension("png")

        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ScreenCaptureCLIArguments.selectionArguments(outputURL: outputURL)
            let errors = Pipe()
            task.standardError = errors
            task.terminationHandler = { process in
                let diagnostic = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    defer {
                        try? FileManager.default.removeItem(at: outputURL)
                    }

                    guard process.terminationStatus == 0 else {
                        // Escape cancellation is silent. Only an actual helper failure is an error.
                        if !diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.lastError = "系统截图未完成（退出码 \(process.terminationStatus)）。请重试；若系统拒绝访问，请核对设置中的应用路径与当前版本。"
                        }
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let data = try? Data(contentsOf: outputURL), let image = NSImage(data: data) else {
                        self.lastError = "系统未生成可读取的截图，请重新框选。"
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }

            do {
                try task.run()
            } catch {
                lastError = "无法启动系统截图工具。请检查本机 /usr/sbin/screencapture 是否可用。"
                try? FileManager.default.removeItem(at: outputURL)
                continuation.resume(returning: nil)
            }
        }
    }

    @available(macOS 15.2, *)
    private func captureImage(in rect: CGRect) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            if #available(macOS 26.0, *) {
                let configuration = SCScreenshotConfiguration()
                configuration.showsCursor = false
                configuration.dynamicRange = .sdr
                SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration) { output, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image = output?.sdrImage else {
                        continuation.resume(throwing: ScreenCaptureServiceError.missingImage)
                        return
                    }

                    continuation.resume(returning: image)
                }
            } else {
                SCScreenshotManager.captureImage(in: rect) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image else {
                        continuation.resume(throwing: ScreenCaptureServiceError.missingImage)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }

}

private enum ScreenCaptureServiceError: LocalizedError {
    case missingImage

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "ScreenCaptureKit completed without returning an image."
        }
    }
}

@MainActor
protocol RegionSelectionOverlayWindow: AnyObject {
    func orderOut(_ sender: Any?)
    func prepareForReuse()
    func setFrame(_ frame: CGRect, display: Bool)
}

@MainActor
struct RegionSelectionOverlayTeardown {
    init() {}

    func dismiss(_ window: RegionSelectionOverlayWindow?) {
        window?.orderOut(nil)
        window?.prepareForReuse()
    }
}

@MainActor
struct RegionSelectionOverlayPresenter {
    init() {}

    func prepareWindow<Window: RegionSelectionOverlayWindow>(
        existingWindow: Window?,
        frame: CGRect,
        makeWindow: (CGRect) -> Window
    ) -> Window {
        if let existingWindow {
            existingWindow.setFrame(frame, display: false)
            return existingWindow
        }

        return makeWindow(frame)
    }
}

@MainActor
private final class ScreenRegionSelector {
    private let overlayTeardown = RegionSelectionOverlayTeardown()
    private let overlayPresenter = RegionSelectionOverlayPresenter()
    private var overlayWindow: ScreenRegionSelectionWindow?
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            presentOverlay()
        }
    }

    private func presentOverlay() {
        let desktopFrame = NSScreen.screens
            .map(\.frame)
            .reduce(into: CGRect.null) { partialResult, frame in
                partialResult = partialResult.union(frame)
            }

        guard !desktopFrame.isNull else {
            finish(with: nil)
            return
        }

        let window = overlayPresenter.prepareWindow(
            existingWindow: overlayWindow,
            frame: desktopFrame,
            makeWindow: ScreenRegionSelectionWindow.init(frame:)
        )
        overlayWindow = window

        let selectionView = ScreenRegionSelectionView(
            frame: CGRect(origin: .zero, size: desktopFrame.size),
            onComplete: { [weak self] rect in
                self?.finish(with: rect)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        )

        window.contentView = selectionView

        // A nonactivating panel stays on the user's current Space. Activating
        // the app here can switch away from a full-screen paper to the desktop.
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
    }

    private func finish(with rect: CGRect?) {
        guard let continuation else {
            return
        }

        self.continuation = nil

        overlayTeardown.dismiss(overlayWindow)
        continuation.resume(returning: rect)
    }
}

private final class ScreenRegionSelectionWindow: NSPanel, RegionSelectionOverlayWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "ScreenScribe · 选择截图区域"
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    func prepareForReuse() {
        makeFirstResponder(nil)
    }
}

private final class ScreenRegionSelectionView: NSView {
    private let minimumSelectionSize: CGFloat = 4
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(
        frame: CGRect,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(event.locationInWindow)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clamped(event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint, let window else {
            onCancel()
            return
        }

        currentPoint = clamped(event.locationInWindow)
        let selectionRect = normalizedRect(from: startPoint, to: currentPoint ?? startPoint)

        guard selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize else {
            onCancel()
            return
        }

        onComplete(window.convertToScreen(selectionRect))
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let maskPath = NSBezierPath(rect: bounds)
        if let selectionRect = selectionRect {
            maskPath.appendRect(selectionRect)
            maskPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.28).setFill()
        maskPath.fill()

        guard let selectionRect else {
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.14).setFill()
        selectionRect.fill()

        let borderPath = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 2
        NSColor.white.withAlphaComponent(0.95).setStroke()
        borderPath.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return normalizedRect(from: startPoint, to: currentPoint)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func normalizedRect(from startPoint: CGPoint, to endPoint: CGPoint) -> CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(startPoint.x - endPoint.x),
            height: abs(startPoint.y - endPoint.y)
        )
    }
}
#endif
