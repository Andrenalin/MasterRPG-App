// @copyright André Trettin

import CoreServices
import Foundation

public enum UserActivity {
    // used in SIRI, Search
    public static let bundleIdentifierType = "\(BundleIds.legacyProduct).Activity.Detail"
    public static let moduleKey = "module"
    public static let commandKey = "command"
    public static let itemKey = "itemId"
    public static let childKey = "childId"

    public static func extractModule(from text: String) -> NetworkModules {
        switch text.uppercased() {
        case NetworkModules.adventure.token: return .adventure
        case NetworkModules.audio.token: return .audio
        case NetworkModules.dice.token: return .dice
        case NetworkModules.game.token: return .game
        case NetworkModules.generator.token: return .generator
        case NetworkModules.map.token: return .map
        case NetworkModules.pdf.token: return .pdf
        case NetworkModules.photo.token: return .photo
        case NetworkModules.rule.token: return .rule
        case NetworkModules.space.token: return .space
        case NetworkModules.table.token: return .table
        case NetworkModules.value.token: return .value
        case NetworkModules.weather.token: return .weather
        default: return .none
        }
    }

    public static func module(from userActivity: NSUserActivity) -> NetworkModules {
        guard let module = userActivity.userInfo?[UserActivity.moduleKey] as? String else { return .none }
        return extractModule(from: module)
    }

    public static func itemId(from userActivity: NSUserActivity) -> UUID? {
        guard let itemString = userActivity.userInfo?[UserActivity.itemKey] as? String else { return nil }
        return UUID(uuidString: itemString)
    }

    public static func childId(from userActivity: NSUserActivity) -> UUID? {
        guard let childString = userActivity.userInfo?[UserActivity.childKey] as? String else { return nil }
        return UUID(uuidString: childString)
    }

    /// The activity is for Handoff and on-screen context. It is not eligible for search: the same
    /// item is already in Spotlight through the Core Data index and the App Entity index, and an
    /// activity with the generic description "An item from MasterRPG" showed up as a third,
    /// poorer result. See CODE_AUDIT_AppIntents §5.4.
    public static func addPayLoad(for userActivity: NSUserActivity, title: String, module: NetworkModules, itemId: UUID, childId: UUID? = nil) {
        userActivity.isEligibleForSearch = false
        userActivity.isEligibleForHandoff = true
        userActivity.title = title
        var userInfo: [String: String] = [itemKey: itemId.uuidString]
        userInfo[moduleKey] = module.token
        if let childId {
            userInfo[childKey] = childId.uuidString
        }
        userActivity.userInfo = userInfo
    }
}
