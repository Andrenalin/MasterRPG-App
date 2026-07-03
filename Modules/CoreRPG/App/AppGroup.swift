// @copyright André Trettin

import Foundation

public extension UserDefaults {
    static let appGroupString = "group.de.andretrettin.MasterRPG"
    @MainActor static let appGroup = UserDefaults(suiteName: appGroupString)!
    
    // MARK: - UserDefaults Keys
    
    /// Keys for storing dice roller widget and live activity data
    enum DiceKeys {
        /// Main dice configuration data
        public static let diceConfiguration = "diceConfiguration"

        /// Compact dice payload read by widgets and Live Activities
        public static let widgetSnapshot = "diceWidgetSnapshot"
        
        /// Whether a game session is currently active
        public static let isGameActive = "isGameActive"
        
        /// Name of the current game session
        public static let currentGameName = "currentGameName"
        
        /// History of dice rolls
        public static let rollHistory = "rollHistory"
    }
}

public extension FileManager {
    static let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UserDefaults.appGroupString)!
    
    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.de.andretrettin.gamemaster")
}
