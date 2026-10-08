// @copyright André Trettin

import Foundation
import Security

/// The CRDT actor id of this install: a random id created once and kept in `UserDefaults`,
/// together with a marker of the device it was created on.
///
/// The id is the tie-break between two writes with one clock, so two devices must never share
/// it. `UserDefaults` alone is copied by a device transfer or a restored backup, and the new
/// device then wrote with the old one's id. The marker does not travel: when it no longer
/// matches, a new id is created. See CODE_AUDIT_21 §5.16.
enum LocalActorId {
    static let value: String = resolve(
        defaults: .standard,
        deviceMarker: DeviceMarker.current()
    )

    static let actorKey = BundleIds.app("crdtLocalActorId")
    static let markerKey = BundleIds.app("crdtLocalActorDevice")

    /// - Parameter deviceMarker: What identifies this device, `nil` when it cannot be read right
    ///   now (a locked Keychain): the stored id is then used as it is.
    static func resolve(defaults: UserDefaults, deviceMarker: String?) -> String {
        let stored = defaults.string(forKey: actorKey).flatMap { $0.isEmpty ? nil : $0 }
        let storedMarker = defaults.string(forKey: markerKey)
        if let stored {
            guard let deviceMarker else { return stored }
            // An id from before the marker existed is kept and bound to this device.
            if storedMarker == nil {
                defaults.set(deviceMarker, forKey: markerKey)
                return stored
            }
            if storedMarker == deviceMarker { return stored }
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: actorKey)
        if let deviceMarker {
            defaults.set(deviceMarker, forKey: markerKey)
        } else {
            defaults.removeObject(forKey: markerKey)
        }
        return created
    }
}

/// Something that is the same for every launch on one device and is not carried to another.
private enum DeviceMarker {
    #if os(macOS)
    /// The hardware UUID. Migration Assistant copies the login keychain, so a keychain item is
    /// no marker on a Mac.
    static func current() -> String? {
        var bytes = [UInt8](repeating: 0, count: 16)
        var timeout = timespec(tv_sec: 1, tv_nsec: 0)
        guard gethostuuid(&bytes, &timeout) == 0 else { return nil }
        return NSUUID(uuidBytes: bytes).uuidString
    }
    #else
    private static let service = BundleIds.app("crdtDeviceMarker")
    private static let account = "marker"

    /// A random value in the Keychain, stored as "this device only": such an item is left out of
    /// backups and device transfers.
    static func current() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            let marker = UUID().uuidString
            query[kSecReturnData as String] = nil
            query[kSecMatchLimit as String] = nil
            query[kSecValueData as String] = Data(marker.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess ? marker : nil
        default:
            return nil
        }
    }
    #endif
}
