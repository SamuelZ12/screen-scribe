import Foundation
import Carbon
import SwiftUI

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var textShortcut: ShortcutMonitor.KeyboardShortcut? {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.setCodable(textShortcut, forKey: "textShortcut")
            ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        }
    }

    @Published var defaultPromptShortcut: ShortcutMonitor.KeyboardShortcut? {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.setCodable(defaultPromptShortcut, forKey: "defaultPromptShortcut")
            ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
        }
    }

    @Published var selectedModel: String {
        willSet {
            objectWillChange.send()
        }
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "geminiModel")
        }
    }

    private init() {
        textShortcut = UserDefaults.standard.codable(forKey: "textShortcut")

        // Try to load new key first, fall back to old key for migration
        if let shortcut: ShortcutMonitor.KeyboardShortcut = UserDefaults.standard.codable(forKey: "defaultPromptShortcut") {
            defaultPromptShortcut = shortcut
        } else if let oldShortcut: ShortcutMonitor.KeyboardShortcut = UserDefaults.standard.codable(forKey: "latexShortcut") {
            // Migrate old latexShortcut to defaultPromptShortcut
            defaultPromptShortcut = oldShortcut
            UserDefaults.standard.removeObject(forKey: "latexShortcut")
        }

        let storedModel = UserDefaults.standard.string(forKey: "geminiModel")
        let resolvedModel = Config.resolvedGeminiModelID(from: storedModel)
        selectedModel = resolvedModel
        if let migratedModel = Config.persistedGeminiModelMigration(from: storedModel) {
            UserDefaults.standard.set(migratedModel, forKey: "geminiModel")
        }

        if textShortcut == nil {
            textShortcut = ShortcutMonitor.KeyboardShortcut(
                keyCode: kVK_ANSI_T,
                modifiers: [.command, .shift]
            )
        }

        if defaultPromptShortcut == nil {
            defaultPromptShortcut = ShortcutMonitor.KeyboardShortcut(
                keyCode: kVK_ANSI_L,
                modifiers: [.command, .shift]
            )
        }

        ShortcutMonitor.shared.setShortcut(textShortcut, for: .visionOCR)
        ShortcutMonitor.shared.setShortcut(defaultPromptShortcut, for: .defaultPrompt)
    }
}
