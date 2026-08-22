// @copyright André Trettin

import Foundation

public extension URL {
    static let appScheme: String = "RPG"

    var isDeeplink: Bool {
        scheme?.caseInsensitiveCompare(URL.appScheme) == .orderedSame
    }

    var isGmzDocument: Bool {
        pathExtension.caseInsensitiveCompare("gmz") == .orderedSame
    }

    var moduleIdentifier: NetworkModules {
        guard isDeeplink, let host else { return .none }
        return UserActivity.extractModule(from: host)
    }

    var linkNumber: Int {
        guard pathComponents.count > 1,
              let number = Int(pathComponents[1])
        else {
            return 0
        }
        return number
    }

    var itemId: UUID? {
        guard pathComponents.count > 2,
              let uuid = UUID(uuidString: pathComponents[2])
        else {
            return nil
        }
        return uuid
    }

    var childId: UUID? {
        guard pathComponents.count > 3,
              let uuid = UUID(uuidString: pathComponents[3])
        else {
            return nil
        }
        return uuid
    }

    var commandKey: String? {
        // Keyed off the raw path shape, not `childId`'s parse success — a link with 5
        // components but an invalid entry-id segment should still read the command from
        // index 4, not misread the invalid entry-id itself as the command.
        if pathComponents.count > 4 {
            return pathComponents[4]
        }
        guard pathComponents.count > 3 else { return nil }
        return pathComponents[3]
    }
}
