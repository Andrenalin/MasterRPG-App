// @copyright André Trettin

import Foundation
import Security

/// Storage for `GameJoinCodeModel`'s per-device join codes — abstracted behind a protocol so
/// tests/previews can inject an in-memory fake instead of touching the real Keychain.
/// See CODE_AUDIT §6.2.
protocol JoinCodeStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

/// Keychain-backed `JoinCodeStorage`. Each code is stored as a generic password item, scoped
/// to this app (`kSecAttrService`) and readable only while the device is unlocked, only on
/// this device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) — it never syncs via iCloud
/// Keychain and, unlike the `UserDefaults` storage this replaces, is excluded from unencrypted
/// local device backups. See CODE_AUDIT §6.2.
struct KeychainJoinCodeStorage: JoinCodeStorage {
    private let service = "de.andretrettin.MasterRPG.joinCode"

    func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        // Existing item → update just the value; new item → add it with the
        // this-device-only accessibility (only settable at creation, not via update).
        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existsStatus == errSecSuccess {
            let updateAttributes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
