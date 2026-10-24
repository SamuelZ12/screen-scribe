import Foundation
import Security
import CryptoKit

// This helper is compiled once into the ignored signing directory. Rebuilding it
// changes its Keychain identity, so the Python driver refuses automatic upgrades.
struct Request: Decodable {
    let operation: String
    let keychainPath: String
    let service: String
    let account: String
    let password: String?
    let pkcs12Path: String?
    let certificateSHA1: String?
}

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == errSecSuccess else {
        // Never include request data, passwords, private keys, or Keychain values.
        throw Failure(description: "\(operation) failed (OSStatus \(status)). Authentication UI is disabled.")
    }
}

func loginKeychain() throws -> SecKeychain {
    var result: SecKeychain?
    let path = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
    try check(SecKeychainOpen(path, &result), "Open login Keychain")
    guard let result else { throw Failure(description: "Login Keychain was not returned.") }
    return result
}

func openKeychain(_ path: String) throws -> SecKeychain {
    var result: SecKeychain?
    try check(SecKeychainOpen(path, &result), "Open dedicated Keychain")
    guard let result else { throw Failure(description: "Dedicated Keychain was not returned.") }
    return result
}

func path(of keychain: SecKeychain) throws -> String {
    var bytes = [CChar](repeating: 0, count: 4096)
    var count = UInt32(bytes.count)
    try check(SecKeychainGetPath(keychain, &count, &bytes), "Read dedicated Keychain path")
    return String(cString: bytes)
}

func secretQuery(_ request: Request, login: SecKeychain) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: request.service,
     kSecAttrAccount as String: request.account,
     kSecMatchSearchList as String: [login]]
}

func readPassword(_ request: Request, login: SecKeychain) throws -> Data {
    var query = secretQuery(request, login: login)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    try check(SecItemCopyMatching(query as CFDictionary, &result), "Read scoped signing password")
    guard let data = result as? Data, !data.isEmpty else {
        throw Failure(description: "Scoped signing password is missing or invalid.")
    }
    return data
}

func validateCertificate(_ keychain: SecKeychain, expectedSHA1: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassCertificate,
        kSecMatchSearchList as String: [keychain],
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnRef as String: true]
    var result: CFTypeRef?
    try check(SecItemCopyMatching(query as CFDictionary, &result), "Inspect dedicated certificate")
    let certificates = result as? [SecCertificate] ?? []
    let hashes = certificates.map { cert in
        Insecure.SHA1.hash(data: SecCertificateCopyData(cert) as Data)
            .map { String(format: "%02X", $0) }.joined()
    }
    guard hashes.count == 1, hashes[0] == expectedSHA1.uppercased() else {
        throw Failure(description: "Dedicated Keychain certificate does not match the saved fingerprint.")
    }
}

// SecKeychainCreate may add its result to the search list. Restore the exact
// original list and default even on failure; never add the signing KC for use.
func preservingKeychainPreferences<T>(_ body: () throws -> T) throws -> T {
    var originalList: CFArray?
    var originalDefault: SecKeychain?
    try check(SecKeychainCopySearchList(&originalList), "Snapshot Keychain search list")
    try check(SecKeychainCopyDefault(&originalDefault), "Snapshot default Keychain")
    guard let originalList, let originalDefault else {
        throw Failure(description: "Cannot preserve Keychain preferences.")
    }
    func restore() throws {
        var currentList: CFArray?
        var currentDefault: SecKeychain?
        try check(SecKeychainCopySearchList(&currentList), "Read Keychain search list")
        try check(SecKeychainCopyDefault(&currentDefault), "Read default Keychain")
        if currentList == nil || !CFEqual(currentList, originalList) {
            try check(SecKeychainSetSearchList(originalList), "Restore Keychain search list")
        }
        if currentDefault == nil || !CFEqual(currentDefault, originalDefault) {
            try check(SecKeychainSetDefault(originalDefault), "Restore default Keychain")
        }
    }
    do {
        let result = try body()
        try restore()
        return result
    } catch {
        let originalError = error
        do { try restore() } catch {
            throw Failure(description: "Keychain preferences could not be restored. Stop and inspect System Settings.")
        }
        throw originalError
    }
}

func prepare(_ request: Request) throws -> [String: String] {
    guard let password = request.password, !password.isEmpty,
          let pkcs12Path = request.pkcs12Path,
          let fingerprint = request.certificateSHA1 else {
        throw Failure(description: "Preparation input is incomplete.")
    }
    let login = try loginKeychain()
    var existing: CFTypeRef?
    let existingStatus = SecItemCopyMatching(secretQuery(request, login: login) as CFDictionary, &existing)
    guard existingStatus == errSecItemNotFound else {
        if existingStatus == errSecSuccess {
            throw Failure(description: "Scoped signing password already exists; refusing to replace an existing identity.")
        }
        try check(existingStatus, "Check scoped signing password")
        throw Failure(description: "Unexpected scoped password state.")
    }
    return try preservingKeychainPreferences {
        let passwordData = Data(password.utf8)
        var createdKeychain: SecKeychain?
        try passwordData.withUnsafeBytes { bytes in
            try check(SecKeychainCreate(request.keychainPath, UInt32(bytes.count), bytes.baseAddress,
                                        false, nil, &createdKeychain), "Create dedicated Keychain")
        }
        guard let keychain = createdKeychain else {
            throw Failure(description: "Dedicated Keychain was not created.")
        }
        var secretAdded = false
        do {
            // Only Apple's codesign executable receives private-key access.
            var codesignApplication: SecTrustedApplication?
            try check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &codesignApplication),
                      "Identify codesign")
            guard let codesignApplication else { throw Failure(description: "codesign identity is unavailable.") }
            var keyAccess: SecAccess?
            try check(SecAccessCreate("ScreenScribe local signing private key" as CFString,
                                      [codesignApplication] as CFArray, &keyAccess), "Create signing key ACL")
            guard let keyAccess else { throw Failure(description: "Signing key ACL was not created.") }
            let options: [String: Any] = [
                kSecImportExportPassphrase as String: password,
                kSecImportExportKeychain as String: keychain,
                kSecImportExportAccess as String: keyAccess]
            var items: CFArray?
            let pkcs12 = try Data(contentsOf: URL(fileURLWithPath: pkcs12Path))
            try check(SecPKCS12Import(pkcs12 as CFData, options as CFDictionary, &items), "Import signing identity")
            guard let imported = items as? [[String: Any]], imported.count == 1,
                  imported[0][kSecImportItemIdentity as String] != nil else {
                throw Failure(description: "PKCS12 did not contain exactly one signing identity.")
            }
            try validateCertificate(keychain, expectedSHA1: fingerprint)

            // The new password entry is accessible only to this fixed helper.
            // nil is documented to mean the creating application, not all apps.
            var secretAccess: SecAccess?
            try check(SecAccessCreate("ScreenScribe dedicated signing Keychain password" as CFString,
                                      nil, &secretAccess), "Create scoped password ACL")
            guard let secretAccess else { throw Failure(description: "Scoped password ACL was not created.") }
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: request.service,
                kSecAttrAccount as String: request.account,
                kSecValueData as String: passwordData,
                kSecAttrAccess as String: secretAccess,
                kSecUseKeychain as String: login]
            try check(SecItemAdd(add as CFDictionary, nil), "Store scoped signing password")
            secretAdded = true
            guard try readPassword(request, login: login) == passwordData else {
                throw Failure(description: "Scoped password verification failed.")
            }
            let actualPath = try path(of: keychain)
            try check(SecKeychainLock(keychain), "Lock dedicated Keychain")
            return ["keychainPath": actualPath]
        } catch {
            if secretAdded { _ = SecItemDelete(secretQuery(request, login: login) as CFDictionary) }
            _ = SecKeychainDelete(keychain)
            throw error
        }
    }
}

do {
    // This is process-wide and applies to legacy Keychain APIs as well. Do not
    // substitute kSecUseAuthenticationUIFail, which is not enough for them.
    try check(SecKeychainSetUserInteractionAllowed(false), "Disable authentication UI")
    let request = try JSONDecoder().decode(Request.self, from: FileHandle.standardInput.readDataToEndOfFile())
    var response = ["status": "ok"]
    switch request.operation {
    case "prepare":
        response.merge(try prepare(request)) { _, new in new }
    case "unlock":
        guard let fingerprint = request.certificateSHA1 else {
            throw Failure(description: "Certificate fingerprint is missing.")
        }
        let keychain = try openKeychain(request.keychainPath)
        try validateCertificate(keychain, expectedSHA1: fingerprint)
        let password = try readPassword(request, login: loginKeychain())
        try password.withUnsafeBytes { bytes in
            try check(SecKeychainUnlock(keychain, UInt32(bytes.count), bytes.baseAddress, true),
                      "Unlock dedicated Keychain")
        }
    case "lock":
        try check(SecKeychainLock(openKeychain(request.keychainPath)), "Lock dedicated Keychain")
    case "status":
        guard let fingerprint = request.certificateSHA1 else {
            throw Failure(description: "Certificate fingerprint is missing.")
        }
        try validateCertificate(openKeychain(request.keychainPath), expectedSHA1: fingerprint)
        _ = try readPassword(request, login: loginKeychain())
    default:
        throw Failure(description: "Unknown helper operation.")
    }
    let output = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    // Never print Foundation's debugDescription of request-containing objects.
    let message = (error as? Failure)?.description ?? "Signing helper failed; no authentication UI was requested."
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
