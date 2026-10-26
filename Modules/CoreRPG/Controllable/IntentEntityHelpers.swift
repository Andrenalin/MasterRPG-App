// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation
import os.log

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

/// Removes entities from the Spotlight index. A failing index must not fail what the user asked
/// for (the item is already trashed and saved), so the error is logged and the call returns.
/// See CODE_AUDIT_AppIntents §5.8.
public func deleteIntentEntities<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type
) async where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable(), !ids.isEmpty else { return }

    do {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            try await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: ids,
                ofType: entityType
            )
        } else {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
        }
    } catch {
        Logger.appIntents.error("Removing \(ids.count, privacy: .public) \(String(describing: entityType), privacy: .public) from the Spotlight index failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
    }
}

/// Brings the module's App Entity index up to date with what changed since the last run: the ids
/// `itemDataModel` marked (added, edited, trashed, removed) are indexed again, and the ones whose
/// item is gone, trashed or not `isIndexable` (e.g. the rule compendium's own categories) leave
/// the index, because the queries hide them and Siri would find an item it cannot open. A run
/// without changes does nothing. The first run per module covers every item and also clears what
/// earlier versions left in the index (everything of the type on iOS 27). Trashing and purging in
/// the UI additionally remove entries at once (`IntentEntityIdentifiers.removeFromIndex`).
/// See CODE_AUDIT_AppIntents §5.3, §7.1.
@MainActor
public func reindexIntentEntities<Entity: IndexedEntity, Model: ItemDataAccessible>(
    itemDataModel: ItemDataModel,
    module: NetworkModules,
    model: (UUID) -> Model?,
    isIndexable: (Model) -> Bool = { _ in true },
    makeEntity: (Model) -> Entity
) async where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable() else { return }

    let prunedKey = "AppEntityIndexPruned.\(module.token)"
    let needsPrune = !UserDefaults.standard.bool(forKey: prunedKey)
    guard itemDataModel.hasIndexChanges || needsPrune else { return }

    let changedIds = itemDataModel.takeIndexDirtyIds()
    let ids = needsPrune ? Array(Set(itemDataModel.items).union(changedIds)) : Array(changedIds)

    var entities: [Entity] = []
    var notIndexed: [UUID] = []
    for id in ids {
        if let model = model(id), model.displayState != DisplayStateMask.totalHidden.rawValue, isIndexable(model) {
            entities.append(makeEntity(model))
        } else {
            notIndexed.append(id)
        }
    }

    if needsPrune {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            do {
                try await CSSearchableIndex.default().deleteAppEntities(ofType: Entity.self)
            } catch {
                Logger.appIntents.error("Clearing the \(module.token, privacy: .public) App Entity index failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                // Not marked as pruned, so the next run tries again; the changes are kept for it.
                changedIds.forEach(itemDataModel.markIndexDirty)
                return
            }
        }
        UserDefaults.standard.set(true, forKey: prunedKey)
    }

    await deleteIntentEntities(ids: notIndexed, ofType: Entity.self)

    do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    } catch {
        Logger.appIntents.error("\(module.token, privacy: .public) reindex failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        // Left marked, so the next run indexes them again.
        entities.forEach { itemDataModel.markIndexDirty($0.id) }
    }
}

#endif
