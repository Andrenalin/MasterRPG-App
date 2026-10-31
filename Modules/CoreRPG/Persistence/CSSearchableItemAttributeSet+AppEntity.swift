// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation

public extension CSSearchableItemAttributeSet {
    /// Ties a Core Data Spotlight item of an entry to the App Entity of its item, on the 27
    /// releases. The App Entity only carries a short excerpt; the Core Data index holds every
    /// entry's full text. With the link Siri can answer from that text and still open or act on
    /// the item it belongs to. `itemId` is the parent item's id.
    ///
    /// Only for entries: the property is for child items of an `IndexedEntity`. The Core Data row
    /// of the item itself must not carry it, the entity indexes that row already, and the system's
    /// translator (`LNSpotlightCascadeTranslator`) logged an error for each of them.
    /// See CODE_AUDIT_AppIntents3 §4.2.
    func relate<Entity: AppEntity>(to entityType: Entity.Type, itemId: UUID?) where Entity.ID == UUID {
        guard let itemId else { return }
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            relatedAppEntityIdentifier = EntityIdentifier(for: entityType, identifier: itemId)
        }
    }
}

#endif
