import Foundation
import Security
import Darwin

// Keep this Objective-C protocol name and method signature identical in the app.
@objc(ScreenScribeCredentialServiceProtocol)
protocol ScreenScribeCredentialServiceProtocol {
    func performOperation(_ operation: String, account: String, value: String?,
                          withReply reply: @escaping (Int32, String?) -> Void)
}

private final class CredentialService: NSObject, ScreenScribeCredentialServiceProtocol {
    private func validAccount(_ account: String) -> Bool {
        guard account.utf8.count <= 4096,
              !account.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        if ["mathpix.id", "mathpix.key", "gemini.key"].contains(account) { return true }
        let verificationPrefix = "verification."
        if account.hasPrefix(verificationPrefix) {
            let suffix = String(account.dropFirst(verificationPrefix.count))
            return suffix.count == 36 && UUID(uuidString: suffix)?.uuidString.lowercased() == suffix.lowercased()
        }
        let prefix = "openai.key."
        guard account.hasPrefix(prefix) else { return false }
        let endpoint = String(account.dropFirst(prefix.count))
        guard !endpoint.isEmpty, !endpoint.contains(where: { $0.isWhitespace }),
              let url = URLComponents(string: endpoint),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        if let port = url.port, !(1...65535).contains(port) { return false }
        return true
    }

    func performOperation(_ operation: String, account: String, value: String?,
                          withReply reply: @escaping (Int32, String?) -> Void) {
        // Foundation checks the requirement on incoming messages, not just an
        // untrusted PID observed before exec. Never send secrets over stdio.
        guard let connection = NSXPCConnection.current(),
              connection.effectiveUserIdentifier == geteuid() else {
            reply(errSecAuthFailed, nil); return
        }
        if operation == "ping" {
            guard account.isEmpty, value == nil else { reply(errSecParam, nil); return }
            reply(errSecSuccess, nil); return
        }
        guard ["read", "save", "delete"].contains(operation), validAccount(account),
              operation == "save" ? (value != nil && value!.utf8.count <= 16384) : value == nil else {
            reply(errSecParam, nil); return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: CredentialXPCPolicy.keychainService,
            kSecAttrAccount as String: account]
        switch operation {
        case "read":
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(request as CFDictionary, &result)
            guard status == errSecSuccess else { reply(status, nil); return }
            guard let data = result as? Data, data.count <= 16384,
                  let text = String(data: data, encoding: .utf8) else {
                reply(errSecDecode, nil); return
            }
            reply(errSecSuccess, text)
        case "save":
            let data = Data(value!.utf8)
            let updated = SecItemUpdate(query as CFDictionary,
                                        [kSecValueData as String: data] as CFDictionary)
            if updated == errSecSuccess { reply(errSecSuccess, nil); return }
            guard updated == errSecItemNotFound else { reply(updated, nil); return }
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            reply(SecItemAdd(item as CFDictionary, nil), nil)
        case "delete":
            let status = SecItemDelete(query as CFDictionary)
            reply(status == errSecItemNotFound ? errSecSuccess : status, nil)
        default:
            reply(errSecParam, nil)
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        // macOS 13+: invalidates the connection if a new message's sender does
        // not satisfy this requirement. Set it before exporting or resuming.
        connection.setCodeSigningRequirement(CredentialXPCPolicy.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: ScreenScribeCredentialServiceProtocol.self)
        connection.exportedObject = CredentialService()
        connection.resume()
        return true
    }
}

@main
private enum CredentialXPCMain {
    static func main() {
        // Covers legacy Keychain ACL dialogs as well as SecItem calls. A locked
        // or inaccessible item returns its status instead of requesting UI.
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { exit(1) }
        let delegate = ListenerDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        withExtendedLifetime(delegate) {
            listener.resume()
            RunLoop.current.run()
        }
    }
}
