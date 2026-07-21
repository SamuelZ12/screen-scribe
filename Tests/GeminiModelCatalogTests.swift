import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct GeminiModelCatalogTests {
    static func main() {
        let modelIDs = Config.availableGeminiModels.map(\.id)

        expect(modelIDs.contains("gemini-3.6-flash"), "Gemini 3.6 Flash should be available")
        expect(modelIDs.contains("gemini-3.1-pro-preview"), "Gemini 3.1 Pro Preview should be available")
        expect(modelIDs.contains("gemini-3.5-flash-lite"), "Gemini 3.5 Flash-Lite should be available")
        expect(!modelIDs.contains("gemini-3.5-flash"), "Gemini 3.5 Flash should be removed from the catalog")
        expect(!modelIDs.contains("gemini-3.1-flash-lite-preview"), "Gemini 3.1 Flash-Lite Preview should be removed from the catalog")
        expect(!modelIDs.contains("gemini-3-flash-preview"), "Gemini 3 Flash Preview should be removed from the catalog")
        expect(!modelIDs.contains("gemini-3-pro-preview"), "Gemini 3 Pro Preview should be removed from the catalog")
        expect(!modelIDs.contains("gemini-2.5-flash-lite"), "Gemini 2.5 Flash-Lite should be removed from the catalog")

        expect(
            Config.defaultGeminiModelID == "gemini-3.6-flash",
            "The default Gemini model should be Gemini 3.6 Flash"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3.5-flash") == "gemini-3.6-flash",
            "Stored Gemini 3.5 Flash selections should migrate to Gemini 3.6 Flash"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3-flash-preview") == "gemini-3.6-flash",
            "Stored Gemini 3 Flash Preview selections should migrate to Gemini 3.6 Flash"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3-pro-preview") == "gemini-3.1-pro-preview",
            "Stored Gemini 3 Pro Preview selections should migrate to Gemini 3.1 Pro Preview"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3.1-flash-lite-preview") == "gemini-3.5-flash-lite",
            "Stored Gemini 3.1 Flash-Lite selections should migrate to Gemini 3.5 Flash-Lite"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3.1-flash-lite") == "gemini-3.5-flash-lite",
            "Stored Gemini 3.1 Flash-Lite stable selections should migrate to Gemini 3.5 Flash-Lite"
        )
        expect(
            Config.migratedGeminiModelID("gemini-2.5-flash-lite") == "gemini-3.5-flash-lite",
            "Stored Gemini 2.5 Flash-Lite selections should migrate to Gemini 3.5 Flash-Lite"
        )
        expect(
            Config.migratedGeminiModelID("gemini-3.6-flash") == "gemini-3.6-flash",
            "Current supported selections should remain unchanged"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-3.5-flash") == "gemini-3.6-flash",
            "The deprecated Gemini 3.5 Flash setting should be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-3-flash-preview") == "gemini-3.6-flash",
            "The deprecated Gemini 3 Flash Preview setting should be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-3-pro-preview") == "gemini-3.1-pro-preview",
            "The deprecated Gemini 3 Pro Preview setting should be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-3.1-flash-lite-preview") == "gemini-3.5-flash-lite",
            "The deprecated Gemini 3.1 Flash-Lite setting should be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-2.5-flash-lite") == "gemini-3.5-flash-lite",
            "The deprecated Gemini 2.5 Flash-Lite setting should be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-3.6-flash") == nil,
            "Supported Gemini selections should not be rewritten in storage"
        )
        expect(
            Config.persistedGeminiModelMigration(from: "gemini-custom-experimental") == nil,
            "Unknown custom Gemini selections should not be overwritten during migration"
        )
        expect(
            Config.requestGeminiModelID(from: "gemini-3.5-flash") == "gemini-3.6-flash",
            "Deprecated Gemini 3.5 Flash requests should be upgraded automatically"
        )
        expect(
            Config.requestGeminiModelID(from: "gemini-3-flash-preview") == "gemini-3.6-flash",
            "Deprecated Gemini 3 Flash Preview requests should be upgraded automatically"
        )
        expect(
            Config.requestGeminiModelID(from: "gemini-3-pro-preview") == "gemini-3.1-pro-preview",
            "Deprecated Gemini 3 Pro Preview requests should be upgraded automatically"
        )
        expect(
            Config.requestGeminiModelID(from: "gemini-3.1-flash-lite-preview") == "gemini-3.5-flash-lite",
            "Deprecated Gemini 3.1 Flash-Lite requests should be upgraded automatically"
        )
        expect(
            Config.requestGeminiModelID(from: "gemini-custom-experimental") == "gemini-custom-experimental",
            "Custom Gemini selections should still be used for requests"
        )
        expect(
            Config.requestGeminiModelID(from: nil) == "gemini-3.6-flash",
            "Missing Gemini selections should still use the default request model"
        )

        print("GeminiModelCatalogTests passed")
    }
}
