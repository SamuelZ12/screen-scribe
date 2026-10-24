import AppKit

@MainActor
final class SettingsWindowController {
    static func showSettings() { (NSApp.delegate as? App)?.showSettings() }
}
