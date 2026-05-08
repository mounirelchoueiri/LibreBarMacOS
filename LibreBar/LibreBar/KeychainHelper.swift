import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.librebar.credentials"
    private static let migratedKey = "keychain_migrated_v2"

    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        if let password = load(account: "libre_password") {
            delete(account: "libre_password")
            save(account: "libre_password", value: password)
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }

    static func save(account: String, value: String) {
        delete(account: account)
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
