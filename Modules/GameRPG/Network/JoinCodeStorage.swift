// @copyright André Trettin

import CoreRPG
import Foundation
import Security
import Synchronization

/// Outcome of reading a join code. "Not stored yet" and "the store could not be read right
/// now" (locked keychain, keychain unavailable before first unlock) need different handling:
/// only the former may generate a fresh code. See CODE_AUDIT §5.5.
enum JoinCodeReadResult: Equatable, Sendable {
    case found(String)
    case notFound
    case unavailable
}

/// Storage for `GameJoinCodeModel`'s per-device join codes — abstracted behind a protocol so
/// tests/previews can inject an in-memory fake instead of touching the real Keychain.
/// See CODE_AUDIT §6.2.
protocol JoinCodeStorage: Sendable {
    func read(forKey key: String) -> JoinCodeReadResult
    /// Returns whether the value was durably stored, so callers only discard a legacy copy
    /// after a verified write. See CODE_AUDIT_16 §5.6.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool
    /// Lets a code be cleared the same way it's set, rather than needing a
    /// separate storage mechanism just for deletion. Returns whether the item is gone.
    @discardableResult
    func remove(forKey key: String) -> Bool
}

extension JoinCodeStorage {
    func string(forKey key: String) -> String? {
        if case .found(let value) = read(forKey: key) { value } else { nil }
    }
}

/// Keychain-backed `JoinCodeStorage`. Each code is stored as a generic password item, scoped
/// to this app (`kSecAttrService`) and readable only while the device is unlocked, only on
/// this device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) — it never syncs via iCloud
/// Keychain and, unlike the `UserDefaults` storage this replaces, is excluded from unencrypted
/// local device backups. See CODE_AUDIT §6.2.
///
/// On macOS new items go to the data-protection keychain, which honours the accessibility
/// class like iOS. Items written by earlier versions live in the legacy file-based keychain;
/// they are read as a fallback and moved over after a verified write. If the data-protection
/// keychain is unavailable to the build (missing entitlement), the legacy keychain keeps
/// working. See CODE_AUDIT_Join §5.6.
struct KeychainJoinCodeStorage: JoinCodeStorage {
    private let service = BundleIds.app("joinCode")

    func read(forKey key: String) -> JoinCodeReadResult {
        #if os(macOS)
        switch read(forKey: key, dataProtection: true) {
        case .found(let value):
            return .found(value)
        case .unavailable:
            // `set` falls back to the legacy keychain when the data-protection keychain is
            // unavailable to the build (e.g. `errSecMissingEntitlement`); reading must do the
            // same, or codes written there could never be read back. A real "locked" state
            // makes the legacy read unavailable too. See CODE_AUDIT_18 §5.17.
            if case .found(let value) = read(forKey: key, dataProtection: false) {
                return .found(value)
            }
            return .unavailable
        case .notFound:
            let legacy = read(forKey: key, dataProtection: false)
            if case .found(let value) = legacy, write(value, forKey: key, dataProtection: true) {
                delete(forKey: key, dataProtection: false)
            }
            return legacy
        }
        #else
        return read(forKey: key, dataProtection: false)
        #endif
    }

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        #if os(macOS)
        if write(value, forKey: key, dataProtection: true) {
            delete(forKey: key, dataProtection: false)
            return true
        }
        return write(value, forKey: key, dataProtection: false)
        #else
        return write(value, forKey: key, dataProtection: false)
        #endif
    }

    @discardableResult
    func remove(forKey key: String) -> Bool {
        #if os(macOS)
        let removedProtected = delete(forKey: key, dataProtection: true)
        let removedLegacy = delete(forKey: key, dataProtection: false)
        return removedProtected && removedLegacy
        #else
        return delete(forKey: key, dataProtection: false)
        #endif
    }

    private func baseQuery(forKey key: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        #if os(macOS)
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        #endif
        return query
    }

    private func read(forKey key: String, dataProtection: Bool) -> JoinCodeReadResult {
        var query = baseQuery(forKey: key, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return .notFound }
            return .found(value)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable
        }
    }

    private func write(_ value: String, forKey key: String, dataProtection: Bool) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key, dataProtection: dataProtection)
        // Update first; only a definite "not found" adds. This avoids a separate existence
        // query and its check-then-add gap. Accessibility is only settable at creation.
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        default:
            return false
        }
    }

    @discardableResult
    private func delete(forKey key: String, dataProtection: Bool) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key, dataProtection: dataProtection) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
