// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

// Helpers every module's `*ManagementIntents.swift` shares: parameter text, the database gate,
// optional file intake, required name and target, and the App Entity index calls (index, delete,
// trash, incremental reindex). They carry no per-module behavior. What does differ per module
// (the `Entity` struct, its `EntityQuery`, `Transferable` and `attributeSet`) stays in each
// module's `*Entity.swift`; `ItemEntityQuery` holds only the query skeleton they share.

/// The plain text of a rich-text intent parameter, or an empty string when none was passed.
public func intentPlainText(from text: AttributedString?) -> String {
    text.map { String($0.characters) } ?? ""
}

/// `original` with `addition` added as a new paragraph. A blank addition changes nothing, and a
/// blank original is replaced instead of keeping leading blank lines.
public func appendingIntentText(_ addition: String, to original: String) -> String {
    let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAddition.isEmpty else { return original }

    let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOriginal.isEmpty else { return trimmedAddition }

    return "\(trimmedOriginal)\n\n\(trimmedAddition)"
}

/// Thrown by an intent that writes when the database did not start in time, so the user hears
/// that nothing was saved instead of "Created". See CODE_AUDIT §5.1.
public struct DatabaseNotReadyError: Error, CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "MasterRPG is not ready yet. Open the app and try again.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the database did not start in time."
        )
    }
}

/// Waits for the database like `DatabaseReadiness.wait()` and throws `DatabaseNotReadyError` when
/// it still cannot take writes after the timeout. Every intent that creates, changes or deletes
/// items starts with this; read-only intents may keep using `DatabaseReadiness.wait()`.
/// See CODE_AUDIT §5.1.
@MainActor
public func requireReadyDatabase() async throws {
    guard await DatabaseReadiness.wait() else { throw DatabaseNotReadyError() }
}

/// The file passed to a Create intent has a type the item cannot hold.
public struct IntentFileTypeError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The file is not a type this item can hold.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the file passed to a Create intent has the wrong type."
        )
    }
}

/// The file passed to a Create intent could not be stored with the new item.
public struct IntentFileStoreError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The file could not be added.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the file passed to a Create intent could not be stored."
        )
    }
}

/// The bytes of the optional file parameter of a Create intent, or `nil` when none was passed.
/// Throws `IntentFileTypeError` before anything is created when the file is not one of the types
/// the module holds, so a wrong file leaves no empty item behind. See CODE_AUDIT_AppIntents2 §4.4.
public func intentFileData(_ file: IntentFile?, allowedTypes: [UTType]) throws -> Data? {
    guard let file else { return nil }
    let type = file.type ?? UTType(filenameExtension: URL(filePath: file.filename).pathExtension)
    guard let type, allowedTypes.contains(where: { type.conforms(to: $0) }) else {
        throw IntentFileTypeError()
    }
    return file.data
}

/// Stores the file of a just-created item through `store`, which reports whether it worked. When it
/// did not, the item is removed again and `IntentFileStoreError` is thrown: a media item without
/// its media is not what the user asked for.
@MainActor
public func attachIntentFile<Controller: EditControllable>(
    to itemId: UUID,
    editControllable: Controller,
    store: () async throws -> Bool
) async throws {
    let stored = (try? await store()) ?? false
    guard stored, editControllable.editModel(for: itemId)?.fileUrl != nil else {
        await editControllable.delete(itemId: itemId)
        throw IntentFileStoreError()
    }
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

/// Indexes entities right after an intent saved them, so a follow-up Siri request finds them. The
/// item is already saved and the invalidator indexes it anyway, so a failing index is logged and
/// does not fail the intent (a retry of a "failed" create would make a duplicate).
/// See CODE_AUDIT §5.3.
public func indexIntentEntities<Entity: IndexedEntity>(_ entities: [Entity]) async {
    guard CSSearchableIndex.isIndexingAvailable(), !entities.isEmpty else { return }
    do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    } catch {
        Logger.appIntents.error("Indexing \(entities.count, privacy: .public) \(String(describing: Entity.self), privacy: .public) failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
    }
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

/// What every Delete intent does: moves the items to the trash, saves, and takes them out of the
/// Spotlight index. The trash is recoverable, and the dialog stays with the intent because each
/// module localizes it from its own bundle. See CODE_AUDIT_AppIntents §9.3.
@MainActor
public func trashIntentItems<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type,
    in root: some ItemRootControllable
) async where Entity.ID == UUID {
    for id in ids {
        root.editControllable.markForDeletion(itemId: id)
    }
    await root.itemControllable.save()
    await deleteIntentEntities(ids: ids, ofType: entityType)
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
