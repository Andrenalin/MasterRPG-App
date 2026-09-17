// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation

/// Shared Spotlight indexing/deletion glue for `*ManagementIntents.swift`
/// across every module — every module previously hand-copied the same
/// `intentPlainText`/`indexIntentEntities`/`deleteIntentEntities` bodies
/// verbatim. Unlike the per-`Entity`-type `EntityQuery`/`IndexedEntity`/
/// `Transferable`/`attributeSet` conformances (deliberately left
/// per-module — see `ItemEntityQuery`'s doc comment and
/// `Docu/CODE_AUDIT_10.md` §9.3 for why those carry Siri/Shortcuts/Spotlight
/// regression risk that needs device-level verification), these three
/// functions are plain `CSSearchableIndex` CRUD wrappers with zero
/// per-module behavioral difference, so extracting them carries none of
/// that risk. See CODE_AUDIT_Table §9.3.
public func intentPlainText(from text: AttributedString?) -> String {
    text.map { String($0.characters) } ?? ""
}

public func indexIntentEntities<Entity: IndexedEntity>(_ entities: [Entity]) async throws {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    try await CSSearchableIndex.default().indexAppEntities(entities)
}

public func deleteIntentEntities<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type
) async throws where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable() else { return }

    if #available(iOS 27, macOS 27, visionOS 27, *) {
        try await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: ids,
            ofType: entityType
        )
    } else {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
    }
}

#endif
