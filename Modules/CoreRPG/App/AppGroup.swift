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

    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: cloudContainerIdentifier)

    /// The preferred storage root, in order: the iCloud ubiquity container,
    /// then the App Group container, then `URL.documentsDirectory` — falls
    /// back rather than crashing when neither iCloud nor the App Group is
    /// available (an entitlement/signing mismatch, not just a theoretical
    /// case; see `groupURL`/`cloudURL`'s own doc comments). Centralizes what
    /// was previously the same fallback chain hand-copied into 4 separate
    /// files. See CODE_AUDIT §9.3.
    static var preferredRootUrl: URL {
        cloudURL ?? groupURL ?? URL.documentsDirectory
    }
}
