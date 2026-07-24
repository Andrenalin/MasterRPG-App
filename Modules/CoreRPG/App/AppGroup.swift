// @copyright André Trettin

import Foundation

public extension UserDefaults {
    static let appGroupString = "group.de.andretrettin.MasterRPG"
    @MainActor static let appGroup = UserDefaults(suiteName: appGroupString)!
    
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
    static let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UserDefaults.appGroupString)!
    
    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.de.andretrettin.gamemaster")
}
