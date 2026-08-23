// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of GameController+MapSync.swift (renamed +Sync.swift) — this is
// demo-mode-only content, not part of the production sync path.
// See CODE_AUDIT_Game §9.25.

extension GameController {
    @MainActor
    func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType? {
        let item = gameItem(for: itemId)
        if restart {
            item.entries.forEach {
                item.toggle($0.id)
            }
            return networkMapUpdate(for: itemId)
        }
        guard let firstEntry = item.entries.first(where: { !$0.isShown }) else { return nil }
        item.toggle(firstEntry.id)
        return networkMapUpdate(for: itemId)
    }
}
