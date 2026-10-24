import Foundation

@main struct PhysicsSettingsConcurrencyTests {
    @MainActor
    static func main() async throws {
        let suite = "screenscribe.tests.settings-concurrency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        func setup(backend: RecognitionBackend = .mathpix) -> (PhysicsSettings, Reads) {
            let reads = Reads()
            let settings = PhysicsSettings(defaults: defaults, readCredential: reads.read)
            settings.backend = backend
            settings.baseURL = "https://first.test/v1"
            settings.model = "first-model"
            return (settings, reads)
        }

        // Replacing credentials while the first read is suspended must win.
        do {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0]?.account == "mathpix.id" }
            let replacement = configuration(appID: "fake-new-app", key: "fake-new-key")
            try settings.rememberCredentials(replacement)
            reads.succeed(0, value: "fake-old-app")
            await expectCancelled(pending)
            expect(settings.cachedCredentials()?.appID == replacement.appID && settings.cachedCredentials()?.key == replacement.apiKey,
                   "a late App ID read cannot replace newer cached credentials")
            expect(reads.nextID == 1, "a superseded read stops before requesting a key")
        }

        // The same protection is required when the App ID has already returned.
        do {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0] != nil }
            reads.succeed(0, value: "fake-old-app")
            await waitUntil { reads.pending[1]?.account == "mathpix.key" }
            try settings.rememberCredentials(configuration(appID: "fake-new-app", key: "fake-new-key"))
            reads.succeed(1, value: "fake-old-key")
            await expectCancelled(pending)
            expect(settings.cachedCredentials()?.appID == "fake-new-app" && settings.cachedCredentials()?.key == "fake-new-key",
                   "a late key read cannot overwrite a replacement configuration")
        }

        // Deletion must invalidate pending reads even when no cache existed yet.
        do {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0] != nil }
            settings.forgetCredentials()
            reads.succeed(0, value: "fake-deleted-app")
            await expectCancelled(pending)
            expect(settings.cachedCredentials() == nil && reads.nextID == 1,
                   "deletion prevents an outstanding read from reviving credentials")
        }

        // A provider round trip must not make an earlier read current again.
        do {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0] != nil }
            settings.backend = .openAI
            settings.backend = .mathpix
            reads.succeed(0, value: "fake-old-app")
            await expectCancelled(pending)
            expect(settings.cachedCredentials() == nil && reads.nextID == 1,
                   "changing backend invalidates old reads even after switching back")
        }

        // Endpoint and model changes invalidate the single OpenAI credential read.
        for changeModel in [false, true] {
            let (settings, reads) = setup(backend: .openAI)
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0]?.account == "openai.key.https://first.test/v1/chat/completions" }
            if changeModel { settings.model = "second-model" }
            else { settings.baseURL = "https://second.test/v1" }
            reads.succeed(0, value: "fake-old-endpoint-key")
            await expectCancelled(pending)
            if !changeModel { settings.baseURL = "https://first.test/v1" }
            expect(settings.cachedCredentials() == nil, "changing endpoint or model cannot cache an old read")
        }

        // Cancellation is checked after both independent credential awaits.
        for cancelKeyRead in [false, true] {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0] != nil }
            if cancelKeyRead {
                reads.succeed(0, value: "fake-cancelled-app")
                await waitUntil { reads.pending[1] != nil }
                pending.cancel()
                reads.succeed(1, value: "fake-cancelled-key")
            } else {
                pending.cancel()
                reads.succeed(0, value: "fake-cancelled-app")
            }
            await expectCancelled(pending)
            expect(settings.cachedCredentials() == nil, "a cancelled task never caches late credential reads")
            expect(reads.nextID == (cancelKeyRead ? 2 : 1), "cancellation stops before any unnecessary next read")
        }

        // A current read can still complete, and cached reuse performs no reads.
        do {
            let (settings, reads) = setup()
            let pending = Task { try await settings.configuration() }
            await waitUntil { reads.pending[0] != nil }
            reads.succeed(0, value: "fake-current-app")
            await waitUntil { reads.pending[1] != nil }
            reads.succeed(1, value: "fake-current-key")
            let loaded = try await pending.value
            expect(loaded.backend == .mathpix && loaded.model == "first-model" && loaded.baseURL == "https://first.test/v1",
                   "an unchanged selection returns its captured configuration")
            expect(loaded.appID == "fake-current-app" && loaded.apiKey == "fake-current-key", "current reads return both credentials")
            let cached = try await settings.configuration()
            expect(cached.appID == loaded.appID && cached.apiKey == loaded.apiKey && reads.nextID == 2,
                   "cached configuration reuses credentials without a keychain read")
            settings.forgetCredentials()
        }

        let stored = String(describing: defaults.persistentDomain(forName: suite) ?? [:])
        expect(!stored.contains("fake-") && !stored.contains("key"), "injected credentials never enter UserDefaults")
        print("PhysicsSettingsConcurrencyTests passed: replacement, deletion, provider/endpoint/model changes, cancellation after either read and cached reuse")
    }

    private static func configuration(appID: String, key: String) -> RecognitionConfiguration {
        RecognitionConfiguration(backend: .mathpix, model: "first-model", baseURL: "https://first.test/v1", appID: appID, apiKey: key)
    }

    @MainActor private static func expectCancelled(_ task: Task<RecognitionConfiguration, Error>) async {
        do { _ = try await task.value; fatalError("a superseded credential read must be cancelled") }
        catch is CancellationError {}
        catch { fatalError("unexpected cancellation error type") }
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("a suspended credential read did not arrive")
    }

    @MainActor private final class Reads {
        struct Pending {
            let account: String
            let continuation: CheckedContinuation<String, Error>
        }
        var pending: [Int: Pending] = [:]
        var nextID = 0

        func read(_ account: String) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                pending[nextID] = Pending(account: account, continuation: continuation)
                nextID += 1
            }
        }

        func succeed(_ id: Int, value: String) {
            pending.removeValue(forKey: id)!.continuation.resume(returning: value)
        }
    }
}
