import Foundation

@main struct HistoryPersistenceTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenscribe-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let config = RecognitionConfiguration(backend: .openAI, model: "vision-test", baseURL: "https://example.test/v1", appID: "secret-id-never-save", apiKey: "secret-key-never-save")
        let history = RecognitionHistory(url: url)
        let id = try history.add(mode: .feynman, configuration: config, output: RecognitionOutput(code: "test-code", structure: "structure", warnings: ["uncertain arrow"]), png: Data([1,2,3]))
        let restored = RecognitionHistory(url: url)
        expect(restored.records.count == 1 && restored.records[0].png == Data([1,2,3]), "persist image and record")
        expect(restored.records[0].model == "vision-test" && restored.records[0].output.structure == "structure", "record metadata")
        try restored.update(id: id, code: "edited-code")
        expect(RecognitionHistory(url: url).records[0].output.code == "edited-code", "save edits")
        let raw = try String(contentsOf: url, encoding: .utf8)
        expect(!raw.contains("secret-key") && !raw.contains("secret-id"), "no credentials in history")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        expect((attributes[.posixPermissions] as? Int) == 0o600, "private file permissions")
        try restored.removeImages()
        expect(RecognitionHistory(url: url).records[0].png == nil, "remove retained screenshots")
        try restored.remove(id: id); expect(restored.records.isEmpty, "delete record")
        for i in 0..<52 { _ = try restored.add(mode: .equation, configuration: config, output: RecognitionOutput(code: "x=\(i)"), png: nil) }
        expect(restored.records.count == 50 && restored.records.first?.output.code == "x=51", "bounded newest-first history")
        try restored.clear(); expect(RecognitionHistory(url: url).records.isEmpty, "clear persists")
        try Data("corrupt".utf8).write(to: url)
        let corrupt = RecognitionHistory(url: url)
        expect(!corrupt.error.isEmpty, "corruption visible")
        do { _ = try corrupt.add(mode: .equation, configuration: config, output: RecognitionOutput(code:"x"), png:nil); fatalError("corruption overwritten") } catch {}
        let damaged = try String(contentsOf: url, encoding: .utf8)
        expect(damaged == "corrupt", "preserve original damaged data")
        try corrupt.clear(); expect(RecognitionHistory(url: url).error.isEmpty, "explicit clear recovers")
        let suiteName = "screenscribe-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = PhysicsSettings(defaults: defaults)
        settings.mode = .feynman; settings.backend = .openAI; settings.model = "saved-model"; settings.persistImages = true
        let reloaded = PhysicsSettings(defaults: defaults)
        expect(reloaded.mode == .feynman && reloaded.backend == .openAI && reloaded.model == "saved-model" && reloaded.persistImages, "settings survive reconstruction")
        let session = RecognitionConfiguration(backend: .openAI, model: "saved-model", baseURL: reloaded.baseURL, appID: "", apiKey: "only-in-memory")
        try reloaded.rememberCredentials(session)
        let active = try await reloaded.configuration()
        expect(active.apiKey == "only-in-memory", "test/save credentials are reused without repeated Keychain access")
        expect(!defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("only-in-memory") }, "session credential cache never enters UserDefaults")
        reloaded.baseURL = "https://different.test/v1"
        expect(reloaded.cachedCredentials() == nil, "session cache remains endpoint scoped")
        reloaded.baseURL = session.baseURL
        reloaded.forgetCredentials()
        expect(reloaded.cachedCredentials() == nil, "delete clears in-memory credentials")
        print("HistoryPersistenceTests passed: persistence, edits, metadata, deletion, image opt-out, cap, permissions, corruption, no secret serialization and settings restart")
    }
}
