import Foundation
import AppKit
import Security

@main struct KeychainClipboardSmokeTests {
    @MainActor static func main() throws {
        let account = "smoke-test.\(UUID())"
        defer { try? CredentialStore.delete(account) }
        try CredentialStore.save("synthetic-value", account: account)
        var allowsInteraction: DarwinBoolean = true
        precondition(SecKeychainGetUserInteractionAllowed(&allowsInteraction) == errSecSuccess && !allowsInteraction.boolValue,
                     "legacy keychain interaction must remain disabled")
        let read = try CredentialStore.read(account)
        guard read == "synthetic-value" else { fatalError("Keychain roundtrip") }
        try CredentialStore.save("updated-synthetic-value", account: account)
        let updated = try CredentialStore.read(account)
        guard updated == "updated-synthetic-value" else { fatalError("Keychain update") }
        try CredentialStore.delete(account)
        let empty = try CredentialStore.read(account)
        guard empty.isEmpty else { fatalError("Keychain delete") }
        // Restore all existing pasteboard item types after the roundtrip.
        let previous: [NSPasteboardItem] = NSPasteboard.general.pasteboardItems?.map { item in
            let clone = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { clone.setData(data, forType: type) } }
            return clone
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(previous) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(LatexCopyFormat.display.wrap("x^2+1"), forType: .string),
              NSPasteboard.general.string(forType: .string) == "\\[\nx^2+1\n\\]" else { fatalError("clipboard roundtrip") }
        print("KeychainClipboardSmokeTests passed: synthetic Keychain add/read/update/delete; clipboard write/read/restore")
    }
}
