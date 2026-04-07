import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing API keys securely.
enum KeychainHelper {

    static func save(key: String, service: String) -> Bool {
        let data = Data(key.utf8)
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - MiniFlow-specific keys

extension KeychainHelper {
    private static let smallestKeyService = "com.smallestai.MiniFlow.smallest-api-key"

    static var smallestAPIKey: String? {
        get { load(service: smallestKeyService) }
        set {
            if let key = newValue {
                _ = save(key: key, service: smallestKeyService)
            } else {
                delete(service: smallestKeyService)
            }
        }
    }
}
