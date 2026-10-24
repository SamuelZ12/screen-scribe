import Foundation
import Combine

@MainActor
final class PhysicsSettings: ObservableObject {
    typealias CredentialReader = @MainActor (String) async throws -> String
    static let shared = PhysicsSettings()
    @Published var backend: RecognitionBackend {
        didSet {
            defaults.set(backend.rawValue, forKey: "physics.backend")
            if oldValue != backend { credentialRevision = UUID() }
        }
    }
    @Published var mode: RecognitionMode { didSet { defaults.set(mode.rawValue, forKey: "physics.mode") } }
    @Published var model: String {
        didSet {
            defaults.set(model, forKey: "physics.model")
            if oldValue != model { credentialRevision = UUID() }
        }
    }
    @Published var baseURL: String {
        didSet {
            defaults.set(baseURL, forKey: "physics.baseURL")
            if oldValue != baseURL { credentialRevision = UUID() }
        }
    }
    @Published var persistImages: Bool { didSet { defaults.set(persistImages, forKey: "physics.persistImages") } }
    private var sessionCredentials: [String: (appID: String, key: String)] = [:]
    private var credentialRevision = UUID()
    private let defaults: UserDefaults
    private let readCredential: CredentialReader
    private let usageStore: MathpixUsageStore
    private let creditStore: MathpixCreditStore
    init(defaults: UserDefaults = .standard,
         readCredential: @escaping CredentialReader = { try await CredentialStore.readAsync($0) },
         usageStore: MathpixUsageStore? = nil, creditStore: MathpixCreditStore? = nil) {
        self.defaults = defaults
        self.readCredential = readCredential
        self.usageStore = usageStore ?? .shared
        self.creditStore = creditStore ?? .shared
        backend = RecognitionBackend(rawValue: defaults.string(forKey: "physics.backend") ?? "") ?? .mathpix
        mode = RecognitionMode(rawValue: defaults.string(forKey: "physics.mode") ?? "") ?? .equation
        model = defaults.string(forKey: "physics.model") ?? ""
        baseURL = defaults.string(forKey: "physics.baseURL") ?? "https://api.openai.com/v1"
        persistImages = defaults.bool(forKey: "physics.persistImages")
    }
    private func credentialScope() throws -> String {
        backend == .mathpix ? "mathpix.key" : try OpenAICompatibleVisionProvider.credentialAccount(baseURL: baseURL)
    }
    func rememberCredentials(_ configuration: RecognitionConfiguration) throws {
        let scope = configuration.backend == .mathpix ? "mathpix.key" : try OpenAICompatibleVisionProvider.credentialAccount(baseURL: configuration.baseURL)
        credentialRevision = UUID()
        sessionCredentials[scope] = (configuration.appID, configuration.apiKey)
        if configuration.backend == .mathpix {
            usageStore.selectAccount(appID: configuration.appID)
            creditStore.selectAccount(appID: configuration.appID)
        }
    }
    func forgetCredentials() {
        credentialRevision = UUID()
        if let scope = try? credentialScope() { sessionCredentials.removeValue(forKey: scope) }
        if backend == .mathpix {
            usageStore.clearAccount()
            creditStore.clearAccount()
        }
    }
    func refreshMathpixUsage(using configuration: RecognitionConfiguration) {
        guard backend == .mathpix, configuration.backend == .mathpix,
              let current = cachedCredentials(), current.appID == configuration.appID,
              current.key == configuration.apiKey else { return }
        usageStore.refresh(configuration: configuration) { [weak self] snapshot in
            guard let self, self.backend == .mathpix, let current = self.cachedCredentials(),
                  current.appID == snapshot.appID, current.appID == configuration.appID,
                  current.key == configuration.apiKey else { return }
            self.creditStore.reconcileUsage(imageCount: snapshot.imageCount, periodStart: snapshot.periodStart)
        }
    }
    func completedMathpixRequest(using configuration: RecognitionConfiguration) {
        guard backend == .mathpix, configuration.backend == .mathpix,
              let current = cachedCredentials(), current.appID == configuration.appID,
              current.key == configuration.apiKey else { return }
        if creditStore.recordCompletion(appID: configuration.appID) {
            refreshMathpixUsage(using: configuration)
        }
    }
    func cachedCredentials() -> (appID: String, key: String)? {
        guard let scope = try? credentialScope() else { return nil }
        return sessionCredentials[scope]
    }
    func configuration() async throws -> RecognitionConfiguration {
        try Task.checkCancellation()
        let backend = backend, model = model, baseURL = baseURL
        let account = try credentialScope()
        if let cached = sessionCredentials[account] {
            return RecognitionConfiguration(backend: backend, model: model, baseURL: baseURL, appID: cached.appID, apiKey: cached.key)
        }
        let revision = credentialRevision
        func checkCurrent() throws {
            try Task.checkCancellation()
            guard credentialRevision == revision, self.backend == backend, self.model == model,
                  self.baseURL == baseURL, (try? credentialScope()) == account else {
                throw CancellationError()
            }
        }
        // Keychain reads may finish after cancellation. Never let a late read undo
        // newer credentials, deletion, or a change of provider/endpoint/model.
        let appID: String
        if backend == .mathpix {
            appID = try await readCredential("mathpix.id")
            try checkCurrent()
        } else { appID = "" }
        let key = try await readCredential(account)
        try checkCurrent()
        let configuration = RecognitionConfiguration(backend: backend, model: model, baseURL: baseURL, appID: appID, apiKey: key)
        try rememberCredentials(configuration)
        return configuration
    }
}
