// @copyright André Trettin

import Foundation

public extension UserDefaults {
    static let appGroupString = "group.de.andretrettin.MasterRPG"

    /// `nil` when the App Group entitlement/provisioning profile doesn't grant access to
    /// `appGroupString` — an entitlement/signing mismatch across the 5 targets that share
    /// this group, not just a theoretical case. Callers must not force-unwrap this; either
    /// surface a recoverable `CoreDataInitError` (see `CoreDataInitModel.error`) or fall back
    /// to a device-local location. See CODE_AUDIT §5.1.
    @MainActor static let appGroup = UserDefaults(suiteName: appGroupString)

    /// The same suite as `appGroup`, usable from any isolation. `UserDefaults` is not `Sendable`
    /// in the SDK, so this hands out a fresh handle (all handles share one backing store) instead
    /// of a shared global. Every site that needs the shared defaults goes through this one
    /// accessor rather than repeating the suite name. See CODE_AUDIT_15 §9.19.
    nonisolated static var appGroupDefaults: UserDefaults? { UserDefaults(suiteName: appGroupString) }

    // MARK: - UserDefaults Keys
    
    /// Keys for storing dice roller widget data
    enum DiceKeys {
        /// Main dice configuration data
        public static let diceConfiguration = "diceConfiguration"

        /// Compact dice payload read by widgets
        public static let widgetSnapshot = "diceWidgetSnapshot"
        
        /// History of dice rolls
        public static let rollHistory = "rollHistory"
    }
}

public extension FileManager {
    /// Shared iCloud container identifier — also used by
    /// `CloudKitCoreDataPersistenceController` for its
    /// `NSPersistentCloudKitContainerOptions`.
    static let cloudContainerIdentifier = "iCloud.de.andretrettin.gamemaster"

    /// `nil` when the App Group entitlement/provisioning profile doesn't grant access —
    /// see `UserDefaults.appGroup` and CODE_AUDIT §5.1. Callers must not force-unwrap this.
    static let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UserDefaults.appGroupString)

    /// Always `nil` on tvOS: `MasterTV`'s (and `RPGShare`'s) entitlements
    /// deliberately don't declare `com.apple.developer.ubiquity-container-
    /// identifiers`, matching `AppModel`'s tvOS Core Data setup, which
    /// likewise hardcodes `useCloudKit: false` — Apple TV is intentionally a
    /// local-only platform, not synced via iCloud. See CODE_AUDIT_10 §5.1/
    /// §6.1. File-backed modules (Audio/Pdf/Photo/Space) fall back to
    /// `groupURL` below there, so an item saved on tvOS won't appear on a
    /// player's other devices and vice versa — an accepted platform
    /// limitation, not a bug, unless that decision changes.
    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: cloudContainerIdentifier)

    /// Touches `cloudURL` (and `groupURL`) from a background context so the one-time
    /// resolution cost — Apple advises against calling
    /// `url(forUbiquityContainerIdentifier:)` on the main thread — lands there instead
    /// of on whichever thread happens to touch `preferredRootUrl` first, which in
    /// practice was usually the main thread during early app/window setup. Call once,
    /// early, off the main actor; `static let` resolves at most once regardless of how
    /// many times or from where this is called. See CODE_AUDIT_17 §5.19.
    @concurrent
    static func prewarmCloudUrls() async {
        _ = cloudURL
        _ = groupURL
    }

    /// The preferred storage root, in order: the iCloud ubiquity container,
    /// then the App Group container, then `URL.documentsDirectory` — falls
    /// back rather than crashing when neither iCloud nor the App Group is
    /// available (an entitlement/signing mismatch, not just a theoretical
    /// case; see `groupURL`/`cloudURL`'s own doc comments). Centralizes what
    /// was previously the same fallback chain hand-copied into 4 separate
    /// files. See CODE_AUDIT §9.3.
    ///
    /// On tvOS this always resolves to `groupURL` (see `cloudURL`'s doc
    /// comment) — device-local, on purpose.
    static var preferredRootUrl: URL {
        cloudURL ?? groupURL ?? URL.documentsDirectory
    }
}
