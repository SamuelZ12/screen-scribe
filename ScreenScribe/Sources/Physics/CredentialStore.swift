import Foundation
import Security
import CryptoKit

enum CredentialStore {
    private static let legacyService = "app.screenscribe.credentials"
    // Keychain ACLs belong to a signing identity. Ad-hoc builds have a different
    // designated requirement after an update, so they must not overwrite an
    // older build's item while retaining its inaccessible ACL. A stable signing
    // certificate yields the same namespace across updates; an ad-hoc build
    // retains its saved credentials across restarts of that exact build.
    private static let service: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var requirementData: CFData?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyData(requirement, [], &requirementData) == errSecSuccess, let requirementData else { return nil }
        let fingerprint = SHA256.hash(data: requirementData as Data).map { String(format: "%02x", $0) }.joined()
        return legacyService + "." + fingerprint
    }()
    // SecItem's authenticationUI option alone does not suppress legacy macOS
    // keychain ACL dialogs. This app never asks SecurityAgent to display UI.
    // Set the process-wide legacy policy once, before any keychain operation.
    private static let nonInteractiveStatus = SecKeychainSetUserInteractionAllowed(false)
    private static func requireNonInteractiveAccess() throws {
        guard nonInteractiveStatus == errSecSuccess else {
            throw RecognitionError.configuration("无法启用钥匙串静默访问，已停止读取。请在设置中输入凭据供本次使用。")
        }
        guard service != nil else {
            throw RecognitionError.configuration("无法确认当前构建的签名身份，已停止钥匙串访问。可输入凭据供本次运行使用。")
        }
    }
    private static func query(_ account: String, serviceName: String? = nil) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: serviceName ?? service!, kSecAttrAccount as String: account]
    }
    static func read(_ account: String) throws -> String {
        try requireNonInteractiveAccess()
        if let response = try helperRequest("read", account: account) {
            if response.status == errSecItemNotFound { return "" }
            guard response.status == errSecSuccess else { throw keychainError(response.status, operation: "读取") }
            return response.value ?? ""
        }
        if let value = try readItem(account) { return value }
        return try readItem(account, serviceName: legacyService) ?? ""
    }
    private static func readItem(_ account: String, serviceName: String? = nil) throws -> String? {
        var request = query(account, serviceName: serviceName)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw keychainError(status, operation: "读取")
        }
        return value
    }
    static func save(_ value: String, account: String) throws {
        try requireNonInteractiveAccess()
        if let response = try helperRequest("save", account: account, value: value) {
            guard response.status == errSecSuccess else { throw keychainError(response.status, operation: "保存") }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw keychainError(status, operation: "保存") }
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw keychainError(added, operation: "保存") }
    }
    static func delete(_ account: String) throws {
        try requireNonInteractiveAccess()
        if let response = try helperRequest("delete", account: account) {
            guard response.status == errSecSuccess || response.status == errSecItemNotFound else {
                throw keychainError(response.status, operation: "删除")
            }
            return
        }
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status, operation: "删除") }
    }
    private static func keychainError(_ status: OSStatus, operation: String) -> RecognitionError {
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
            return .configuration("旧版凭据的钥匙串访问未获当前版本授权。已禁止系统弹窗；请在设置中输入 App ID / Key 并测试连接，即可在本次运行中识别。")
        }
        return .configuration("钥匙串\(operation)失败（\(status)）；不会请求系统密码。可在设置中输入凭据供本次运行使用。")
    }

    // A local self-signed app has no Apple Team ID. Legacy Keychain partitions
    // therefore track its CDHash even when its designated requirement is stable.
    // The optional, immutable embedded service owns these items across builds.
    // Both peers authenticate received messages; no credential is sent before a
    // successful, authenticated ping on the same connection.
    private static func helperRequest(_ operation: String, account: String, value: String? = nil) throws -> CredentialHelperResponse? {
        guard let configuredRequirement = Bundle.main.object(forInfoDictionaryKey: "ScreenScribeCredentialServiceRequirement") else {
            return nil
        }
        guard let requirementText = configuredRequirement as? String else {
            throw RecognitionError.configuration("凭据服务签名配置格式无效，已停止钥匙串操作。")
        }
        guard !requirementText.isEmpty, requirementText.utf8.count <= 4096,
              account.utf8.count <= 4096, (value?.utf8.count ?? 0) <= 16384 else {
            throw RecognitionError.configuration("凭据服务配置或输入无效，已停止钥匙串操作。")
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            throw RecognitionError.configuration("凭据服务签名要求无效，已停止钥匙串操作。")
        }
        let serviceURL = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/ScreenScribeCredentialHelper.xpc")
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(serviceURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw RecognitionError.configuration("凭据服务未通过固定签名校验，已停止钥匙串操作。")
        }
        let connection = NSXPCConnection(serviceName: "app.screenscribe.CredentialHelper")
        connection.setCodeSigningRequirement(requirementText)
        connection.remoteObjectInterface = NSXPCInterface(with: ScreenScribeCredentialServiceProtocol.self)
        let connectionState = CredentialHelperConnectionState()
        connection.interruptionHandler = { connectionState.invalidate() }
        connection.invalidationHandler = { connectionState.invalidate() }
        connection.activate()
        defer { connection.invalidate() }

        func request(_ operation: String, account: String, value: String?) throws -> CredentialHelperResponse {
            guard connectionState.isValid else {
                throw RecognitionError.configuration("凭据服务连接已中断，未继续发送数据。")
            }
            let pending = CredentialHelperPendingResponse()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                pending.finish(CredentialHelperResponse(status: errSecNotAvailable, value: nil))
            }) as? ScreenScribeCredentialServiceProtocol else {
                throw RecognitionError.configuration("无法连接固定凭据服务。")
            }
            proxy.performOperation(operation, account: account, value: value) { status, result in
                pending.finish(CredentialHelperResponse(status: status, value: result))
            }
            guard pending.semaphore.wait(timeout: .now() + 5) == .success,
                  let response = pending.response, connectionState.isValid else {
                throw RecognitionError.configuration("凭据服务未能完成安全连接；不会请求系统密码。")
            }
            return response
        }

        let ping = try request("ping", account: "", value: nil)
        guard ping.status == errSecSuccess, ping.value == nil else {
            throw RecognitionError.configuration("凭据服务身份确认失败，未发送凭据。")
        }
        return try request(operation, account: account, value: value)
    }
    static func readAsync(_ account: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let completion = CredentialReadCompletion(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                completion.finish(Result { try read(account) })
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                completion.finish(.failure(RecognitionError.configuration("钥匙串静默读取超时。请在设置中输入凭据并测试连接，供本次运行使用。")))
            }
        }
    }
    static func saveAsync(_ value: String, account: String) async throws {
        try await Task.detached(priority: .userInitiated) { try save(value, account: account) }.value
    }
    static func deleteAsync(_ account: String) async throws {
        try await Task.detached(priority: .userInitiated) { try delete(account) }.value
    }
    static func migrateLegacyGemini() throws {
        if let old = UserDefaults.standard.string(forKey: "geminiAPIKey"), !old.isEmpty {
            if try read("gemini.key").isEmpty { try save(old, account: "gemini.key") }
            UserDefaults.standard.removeObject(forKey: "geminiAPIKey")
        }
    }
}

@objc(ScreenScribeCredentialServiceProtocol)
protocol ScreenScribeCredentialServiceProtocol {
    func performOperation(_ operation: String, account: String, value: String?, withReply reply: @escaping (Int32, String?) -> Void)
}

private struct CredentialHelperResponse {
    let status: OSStatus
    let value: String?
}

private final class CredentialHelperConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); valid = false; lock.unlock() }
}

private final class CredentialHelperPendingResponse: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: CredentialHelperResponse?
    var response: CredentialHelperResponse? { lock.lock(); defer { lock.unlock() }; return stored }
    func finish(_ response: CredentialHelperResponse) {
        lock.lock()
        guard stored == nil else { lock.unlock(); return }
        stored = response
        lock.unlock()
        semaphore.signal()
    }
}

private final class CredentialReadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
