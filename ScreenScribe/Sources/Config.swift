import Foundation

/// Manages loading and accessing configuration values from Secrets.plist

struct ConfigurationManager {
    @MainActor
    static let shared = ConfigurationManager()
    
    private let secrets: [String: String]
    
    private init() {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
            self.secrets = dict
        } else {
            print("Error: Could not load Secrets.plist. Please ensure it exists with a GEMINI_API_KEY entry.")
            self.secrets = [:]
        }
    }
    
    func getValue(for key: String) -> String? {
        return secrets[key]
    }
    
    func value(for key: String) -> String? {
        return getValue(for: key)
    }
}

/// Model structure for Gemini AI models
struct GeminiModel: Identifiable {
    let id: String      // raw id used in the URL
    let label: String   // shown to the user
    let note: String?   // optional footnote (speed / cost)
}

/// Central configuration access point for the application
enum Config {
    static let defaultGeminiModelID = "gemini-3.6-flash"

    /// The Gemini API key loaded from Keychain or Secrets.plist
    @MainActor
    static var geminiAPIKey: String {
        if let key = UserDefaults.standard.string(forKey: "geminiAPIKey"), !key.isEmpty {
            return key
        }
        return ConfigurationManager.shared.value(for: "GEMINI_API_KEY") ?? ""
    }
    
    /// Available Gemini models to choose from
    static let availableGeminiModels: [GeminiModel] = [
        .init(id: "gemini-3.6-flash", label: "Gemini 3.6 Flash", note: "Best balance"),
        .init(id: "gemini-3.1-pro-preview", label: "Gemini 3.1 Pro", note: "Most capable"),
        .init(id: "gemini-3.5-flash-lite", label: "Gemini 3.5 Flash-Lite", note: "Fastest"),
    ]

    static func migratedGeminiModelID(_ modelID: String) -> String {
        switch modelID {
        case "gemini-3-flash-preview", "gemini-3.5-flash":
            return "gemini-3.6-flash"
        case "gemini-3-pro-preview":
            return "gemini-3.1-pro-preview"
        case "gemini-2.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.1-flash-lite-preview":
            return "gemini-3.5-flash-lite"
        default:
            return modelID
        }
    }

    static func persistedGeminiModelMigration(from storedModel: String?) -> String? {
        guard let storedModel, !storedModel.isEmpty else {
            return nil
        }

        let candidate = migratedGeminiModelID(storedModel)
        guard candidate != storedModel else {
            return nil
        }

        guard availableGeminiModels.contains(where: { $0.id == candidate }) else {
            return nil
        }

        return candidate
    }

    static func requestGeminiModelID(from storedModel: String?) -> String {
        if let migratedModel = persistedGeminiModelMigration(from: storedModel) {
            return migratedModel
        }

        guard let storedModel, !storedModel.isEmpty else {
            return defaultGeminiModelID
        }

        return storedModel
    }

    static func resolvedGeminiModelID(from storedModel: String?) -> String {
        let candidate = requestGeminiModelID(from: storedModel)
        if availableGeminiModels.contains(where: { $0.id == candidate }) {
            return candidate
        }

        return defaultGeminiModelID
    }
    
    /// Get the Gemini API endpoint for the specified model
    static func geminiEndpoint(for model: String) -> String {
        return "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
    }
}
