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

/// A name or title from Siri or Shortcuts, trimmed. Both can pass an empty or all-whitespace
/// string, so a blank one asks for the value again instead of creating a nameless item or entry.
/// See CODE_AUDIT_AppIntents §5.2.
public func requiredIntentName(
    _ text: String,
    parameter: IntentParameter<String>,
    prompt: IntentDialog
) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw parameter.needsValueError(prompt) }
    return trimmed
}

/// The model behind an entity parameter. The entity can be stale — deleted since Siri or
/// Shortcuts cached it — so a missing model asks for the target again instead of reporting a
/// success that changed nothing. See CODE_AUDIT_AppIntents §5.2.
@discardableResult
public func requiredIntentTarget<Entity: AppEntity, Model>(
    _ model: Model?,
    parameter: IntentParameter<Entity>,
    prompt: IntentDialog
) throws -> Model {
    guard let model else { throw parameter.needsValueError(prompt) }
    return model
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
