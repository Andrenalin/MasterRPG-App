// @copyright André Trettin

import Foundation

public extension UserDefaults {
    static let appGroupString = "group.de.andretrettin.MasterRPG"
    @MainActor static let appGroup = UserDefaults(suiteName: appGroupString)!
}

public extension FileManager {
    static let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.andretrettin.MasterRPG")!
    
    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.de.andretrettin.gamemaster")
}
