import Foundation
import Security

/// Stores the API key of the transcription server in the login keychain. The key never goes to a file.
enum Keychain {
    private static let service = "sk.softverse.OfflineMeetingSummary.internal-asr"
    private static let account = "api-key"

    static func readAsrKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var hasAsrKey: Bool { readAsrKey()?.isEmpty == false }

    @discardableResult
    static func saveAsrKey(_ key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return true }
        var attributes = base
        attributes[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
