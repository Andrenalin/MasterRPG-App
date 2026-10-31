// @copyright André Trettin

import Foundation

public extension UserDefaults {
    static let appGroupString = "group.\(BundleIds.app)"

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
    }
}

public extension FileManager {
    /// Shared iCloud container identifier — also used by
    /// `CloudKitCoreDataPersistenceController` for its
    /// `NSPersistentCloudKitContainerOptions`.
    static let cloudContainerIdentifier = "iCloud.\(BundleIds.product)"

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
    ///
    /// Cached, and re-resolved after the iCloud account or iCloud Drive availability changes
    /// (`NSUbiquityIdentityDidChange`): a `static let` kept the value from launch, so a
    /// session started while iCloud was unavailable wrote to the group container for its
    /// whole lifetime. See CODE_AUDIT_18 §3.3.
    static var cloudURL: URL? {
        CloudContainerCache.shared.url
    }

    /// Resolves `cloudURL` (and `groupURL`) off the main thread — Apple advises against
    /// calling `url(forUbiquityContainerIdentifier:)` there — and starts watching for
    /// iCloud identity changes. Call once, early. The file controllers read the roots lazily
    /// (see `LocationFileManager`), so the first main-thread read no longer races this at
    /// launch. See CODE_AUDIT_17 §5.19 and CODE_AUDIT_18 §3.3.
    @concurrent
    static func prewarmCloudUrls() async {
        CloudContainerCache.shared.startObservingIdentityChanges()
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
