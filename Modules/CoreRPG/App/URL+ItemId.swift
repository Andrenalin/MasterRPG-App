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
        // A 5-component link always carries its command at index 4, regardless of
        // whether index 3 parses as a valid entry id — a link with an invalid
        // entry-id segment should still read the command from index 4, not
        // misread the invalid entry-id itself as the command.
        if pathComponents.count > 4 {
            return pathComponents[4]
        }
        // A 4-component link is ambiguous by count alone: it's either
        // `itemId/entryId` (no command — the common case for a freshly
        // generated entry link) or `itemId/command` (no entry). Only treat
        // index 3 as the command when it does *not* parse as an entry id;
        // otherwise this would misread a bare entry link's id as an
        // unrecognized command and silently drop it (e.g. the auto-toggle
        // that expands a Table link never firing). See CODE_AUDIT_Link.md §9.3.
        guard pathComponents.count > 3, UUID(uuidString: pathComponents[3]) == nil else { return nil }
        return pathComponents[3]
    }
}
