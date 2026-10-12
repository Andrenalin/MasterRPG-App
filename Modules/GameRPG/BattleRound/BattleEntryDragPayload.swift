// @copyright André Trettin

import Foundation

/// The text a dragged battle card carries: its entry id behind a prefix, so
/// any other dropped text is ignored.
enum BattleEntryDragPayload {
    private static let prefix = "masterrpg-battle-entry:"

    static func string(for entryId: UUID) -> String {
        prefix + entryId.uuidString
    }

    static func entryId(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}
