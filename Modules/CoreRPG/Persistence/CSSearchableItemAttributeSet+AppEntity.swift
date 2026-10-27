// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation

public extension CSSearchableItemAttributeSet {
    /// Ties a Core Data Spotlight item (an item or one of its entries) to the App Entity of the
    /// item, on the 27 releases. The App Entity only carries a short excerpt; the Core Data index
    /// holds every entry's full text. With the link Siri can answer from that text and still open
    /// or act on the item it belongs to. `itemId` is the item's id, for an entry its parent's.
    /// See CODE_AUDIT_AppIntents3 §4.2.
    func relate<Entity: AppEntity>(to entityType: Entity.Type, itemId: UUID?) where Entity.ID == UUID {
        guard let itemId else { return }
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            relatedAppEntityIdentifier = EntityIdentifier(for: entityType, identifier: itemId)
        }
    }
}

#endif
