// @copyright André Trettin

import Foundation

public extension UserDefaults {
    @MainActor static let appGroup = UserDefaults(suiteName: "group.de.andretrettin.MasterRPG")!
}

public extension FileManager {
    static let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.andretrettin.MasterRPG")!
    
    static let cloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.de.andretrettin.gamemaster")
}
