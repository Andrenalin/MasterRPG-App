// @copyright André Trettin

import CoreServices
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

public enum UserActivity {
    // used in SIRI, Search
    public static let bundleIdentifierType = "de.AndreTrettin.GameMaster.Activity.Detail"
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

    public static func addPayLoad(for userActivity: NSUserActivity, title: String, module: NetworkModules, itemId: UUID, childId: UUID? = nil) {
        userActivity.isEligibleForSearch = true
        userActivity.isEligibleForHandoff = true
        userActivity.title = title
        var userInfo: [String: String] = [itemKey: itemId.uuidString]
        userInfo[moduleKey] = module.token
        if let childId {
            userInfo[childKey] = childId.uuidString
        }
        userActivity.userInfo = userInfo

        #if !os(tvOS)
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.plainText)

            attributes.contentDescription = "An item from MasterRPG"
            userActivity.contentAttributeSet = attributes
        #endif
    }
}
