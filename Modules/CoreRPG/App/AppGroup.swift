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
}
