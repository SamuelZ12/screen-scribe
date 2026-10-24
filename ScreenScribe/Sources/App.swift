import AppKit
import SwiftUI
import Combine

@MainActor
final class App: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let panel = SnipPanelState()
    private let captureService = ScreenCaptureService()
    private var capturing = false
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "ScreenScribe")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "ScreenScribe · 截图识别"
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }()
    private lazy var popover: NSPopover = {
        let result = NSPopover()
        result.contentSize = NSSize(width: 716, height: 524)
        result.behavior = .semitransient
        result.animates = false
        result.delegate = self
        result.contentViewController = NSHostingController(rootView: SnipPanelView(state: panel))
        return result
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        statusItem.isVisible = true
        PhysicsWorkspace.shared.onPresent = { [weak self] in self?.showPanel(page: .ocr) }
        if let record = RecognitionHistory.shared.records.first { PhysicsWorkspace.shared.load(record, present: false) }
        panel.capture = { [weak self] in self?.initiateScientificCapture() }
        panel.importImage = { [weak self] in self?.importImage() }
        panel.pasteImage = { [weak self] in self?.pasteImage() }
        panel.pinChanged = { [weak self] pinned in self?.popover.behavior = pinned ? .applicationDefined : .semitransient }
        ShortcutMonitor.shared.startMonitoring { [weak self] action in
            switch action {
            case .visionOCR: self?.captureOffline()
            case .defaultPrompt: self?.initiateScientificCapture()
            }
        }
        _ = SettingsManager.shared
        do { try CredentialStore.migrateLegacyGemini() }
        catch { PhysicsWorkspace.shared.error = error.localizedDescription }
        // Normal launch creates only the menu-bar icon. Explicit developer flags use the same popover.
        if CommandLine.arguments.contains("--demo") { PhysicsWorkspace.shared.showDemo() }
        else if CommandLine.arguments.contains("--show-settings") { showSettings() }
        else if CommandLine.arguments.contains("--show-popover") { showPanel() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(); return false
    }
    func applicationWillTerminate(_ notification: Notification) { ShortcutMonitor.shared.stopMonitoring() }

    @objc private func togglePanel(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    func showPanel(page: SnipPanelPage? = nil) {
        if let page { panel.page = page }
        guard let button = statusItem.button else { return }
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showSettings() { showPanel(page: .settings) }
    func showHistory() { showPanel(page: .history) }
    func statusItemInfo() -> (rect: CGRect, screen: NSScreen?)? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return (window.convertToScreen(button.frame), window.screen)
    }
    func initiateScientificCapture() {
        capture { image in
            if CommandLine.arguments.contains("--capture-only") {
                PhysicsWorkspace.shared.presentLocal(image: image, code: "", notice: "框选截图成功 · 本地验证 · 未上传 API")
            } else { PhysicsWorkspace.shared.recognize(image: image) }
        }
    }
    private func capture(_ completion: @escaping (NSImage) -> Void) {
        guard !capturing, !PhysicsWorkspace.shared.busy else { return }
        capturing = true
        popover.performClose(nil)
        Task { @MainActor in
            defer { capturing = false }
            // The service checks the current build without requesting permission.
            if let image = await captureService.captureSelectionImage() {
                ScreenCapturePermissionManager.shared.recordSuccessfulCapture()
                completion(image)
            } else if let error = captureService.lastError {
                PhysicsWorkspace.shared.showError(error)
            } else { showPanel() } // User cancelled; no error and no history entry.
        }
    }
    private func captureOffline() {
        capture { image in
            Task {
                guard let cgImage = image.cgImage else { return }
                let result = await Recognizer.detect(image: cgImage, level: .accurate)
                PhysicsWorkspace.shared.presentLocal(image: image, code: result.lineBreaksJoined, notice: "Apple Vision · 离线文字识别")
            }
        }
    }
    private func captureLegacy(_ prompt: Prompt) {
        capture { image in
            Task {
                do {
                    let key = try await CredentialStore.readAsync("gemini.key")
                    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let data = bitmap.representation(using: .png, properties: [:]) else { throw RecognitionError.malformed }
                    let text = try await GeminiService().extractContent(from: data.base64EncodedString(), apiKey: key, promptContent: prompt.content)
                    PhysicsWorkspace.shared.presentLocal(image: image, code: text, notice: "Gemini · " + prompt.name)
                } catch { PhysicsWorkspace.shared.showError(error.localizedDescription) }
            }
        }
    }
    private func importImage() {
        popover.performClose(nil)
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.png, .jpeg, .tiff, .webP]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.prompt = "识别所选图片"
        picker.begin { [weak self] response in
            Task { @MainActor in
                if response == .OK, let url = picker.url, let image = NSImage(contentsOf: url) {
                    PhysicsWorkspace.shared.recognize(image: image)
                } else { self?.showPanel() }
            }
        }
    }
    @objc private func pasteImage() {
        guard !PhysicsWorkspace.shared.busy else { return }
        guard let image = NSImage(pasteboard: .general) else {
            PhysicsWorkspace.shared.showError("剪贴板中没有图片。请按 ⌃⌘⇧4 框选公式，再点“粘贴截图”；此方式无需授予本应用录屏权限。")
            return
        }
        PhysicsWorkspace.shared.recognize(image: image)
    }
    private func showContextMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title); item.addAction(action); menu.addItem(item)
        }
        add("截图识别") { [weak self] in self?.initiateScientificCapture() }
        add("粘贴截图识别") { [weak self] in self?.pasteImage() }
        add("离线文字识别") { [weak self] in self?.captureOffline() }
        let tools = NSMenuItem(title: "原有 Gemini 提示词")
        let prompts = NSMenu()
        for prompt in PromptManager.shared.prompts {
            let item = NSMenuItem(title: prompt.name)
            item.addAction { [weak self] in self?.captureLegacy(prompt) }; prompts.addItem(item)
        }
        tools.submenu = prompts; menu.addItem(tools); menu.addItem(.separator())
        add("历史记录") { [weak self] in self?.showHistory() }
        add("设置…") { [weak self] in self?.showSettings() }
        menu.addItem(.separator()); add("退出 ScreenScribe") { NSApp.terminate(nil) }
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
    }
    private func setupMainMenu() {
        let main = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu(); item.submenu = appMenu; main.addItem(item)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        let paste = NSMenuItem(title: "粘贴截图识别", action: #selector(pasteImage), keyEquivalent: "v")
        paste.target = self; paste.keyEquivalentModifierMask = [.command, .shift]; appMenu.addItem(paste)
        appMenu.addItem(NSMenuItem(title: "退出 ScreenScribe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit"); editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }
}
