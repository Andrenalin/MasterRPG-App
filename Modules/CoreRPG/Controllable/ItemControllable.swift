// @copyright André Trettin

import Foundation
import Observation
import os.log

public enum GameMutationPolicy: Equatable, Sendable {
    case memoryOnly
    case persist
}

/// Captures persistence errors from legacy edit-controller repair operations.
///
/// Most editor call sites intentionally keep their historical best-effort behaviour.
/// External import installs this reporter only while running its repair pass so a
/// swallowed `replaceSync` error can still abort the transaction and be rolled back.
@MainActor
final class ItemPersistenceFailureReporter {
    private var firstError: (any Error)?

    func record(_ error: any Error) {
        if firstError == nil {
            firstError = error
        }
    }

    func rethrowRecordedError() throws {
        if let firstError {
            throw firstError
        }
    }
}

enum ItemPersistenceFailureScope {
    @TaskLocal static var reporter: ItemPersistenceFailureReporter?
}

extension ItemControllable {
    /// Hands a persistence error to the installed transaction reporter, or, outside such a
    /// transaction, logs and surfaces it the way `save()` does. Without the fallback a failed
    /// write left no trace while the UI showed the edit as saved. See CODE_AUDIT_Folder §3.14.
    @MainActor func recordPersistenceFailure(_ error: any Error, operation: String) {
        if let reporter = ItemPersistenceFailureScope.reporter {
            reporter.record(error)
            return
        }
        let nsError = error as NSError
        Logger.itemController.error("\(operation, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \(error.localizedDescription, privacy: .private)")
        itemDataModel.lastPersistenceError = error
        PersistenceIssueCenter.shared.recordSaveError(error)
    }
}

enum ItemTransactionMutationError: LocalizedError {
    case incompatibleModel

    var errorDescription: String? {
        switch self {
        case .incompatibleModel:
            "The model is incompatible with this item controller."
        }
    }
}

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessible & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistrable & Identifiable & Equatable & Hashable & Codable & ModelType
    
    var cacheControllable: ImageCacheControllable? { get }
    var config: ModuleConfigurable { get }
    var collectionCategory: ItemListCategory { get }
    @MainActor var dataControllable: (any DataPersistenceControllable)? { get }
    var fileUrlDataController: FileUrlDataController? { get }
    
    @MainActor var linkRegisterController: LinkRegisterController { get }
    var itemDataModel: ItemDataModel { get }
    
    @MainActor func children(itemId: UUID) -> [Model]
    @MainActor func subChildren(itemId: UUID, entryId: UUID?) -> [Model]
}

// MARK: - Configuration

public extension ItemControllable {
    var cacheControllable: ImageCacheControllable? { nil }
    var collectionCategory: ItemListCategory { .collection }
    var fileUrlDataController: FileUrlDataController? { nil }

    /// `RootModel.init()` assigns `itemDataModel.linkRegisterController`
    /// shortly after construction, so it's expected to always be present by
    /// the time any conformer's controllers run — but reading it before that
    /// (a Preview, a test, a reset-without-reassign) is a real, if rare,
    /// possibility. A single shared default here — instead of a bare
    /// force-unwrap repeated per module — turns that into a diagnostic
    /// crash message rather than a generic "unexpectedly found nil". See
    /// CODE_AUDIT §5.5.
    @MainActor var linkRegisterController: LinkRegisterController {
        guard let controller = itemDataModel.linkRegisterController else {
            preconditionFailure("\(Self.self) requires a LinkRegisterController after setup.")
        }
        return controller
    }
}

// MARK: - ContextMenuMultiController

public extension ItemControllable {
    @MainActor func collections(isFolder: Bool, in parentId: UUID?) -> [Model] {
        return itemDataModel.items.compactMap { itemId -> Model? in
            guard let item = itemSync(for: itemId),
                  item.displayState == DisplayStateMask.fullVisible.rawValue && item.parentId == parentId && (item.category == (isFolder ? .folder : collectionCategory)) else { return nil }
            return item
        }
    }
}

// MARK: - EditControllable

public extension ItemControllable {
    @MainActor func addNew(type: ItemListCategory) async -> UUID {
        await CloudKitOperationCounter.shared.recordOperation(
            function: "ItemControllable.addNew(type:\(type))",
            file: "ItemControllable.swift"
        )
        
        var model = Model.empty.copy()
        model.category = type
        // Protects the new item from the sync-deletion diff until its insert commits, also when
        // another module's failed save rolls it back. Marked before `replace`: a save by another
        // module during its suspension could commit the insert first, and nothing would then
        // clear the mark. See CODE_AUDIT_19 §5.4, CODE_AUDIT_20 §3.3.
        dataControllable?.markUnsavedInsert(id: model.id)
        do {
            try await dataControllable?.replace(id: model.id, with: model)
        } catch {
            // Every sibling mutation below records a failed write instead of silently
            // proceeding as if it succeeded; this path was the one exception. See
            // CODE_AUDIT_EditItem §5.8.
            recordPersistenceFailure(error, operation: "ItemControllable.addNew")
        }
        resetModel(with: model)
        await save()
        return model.id
    }

    @MainActor func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }
    
    @MainActor func delete(itemId: UUID, withFileData: Bool = true, withDatabase: Bool = true) async {
        guard let item = itemSync(for: itemId) else { return }

        // Leave memory before the first suspension: from here on no editor, import or sync
        // can find the item and queue a fresh upsert for it while the deletion below awaits.
        // Removing it last left that window open for the whole delete. See CODE_AUDIT_Folder §3.9.
        itemDataModel.resetModel(id: item.id)

        // Drop any not-yet-flushed queued edit for this id — including on the
        // memory-only sync-deletion path (`withDatabase == false`), which
        // otherwise never touches the pending-operations queue at all: a local
        // edit queued just before a remote deletion notification arrives would
        // resurrect the item as a fresh insert on the next flush. See
        // CODE_AUDIT_17 §5.7.
        await dataControllable?.removePendingOperations(for: itemId)

        for entry in item.entries {
            await cacheControllable?.remove(itemId: entry.id)
        }

        if withDatabase {
            await CloudKitOperationCounter.shared.recordOperation(
                function: "ItemControllable.delete(itemId:withFileData:\(withFileData))",
                file: "ItemControllable.swift"
            )
            do {
                try await dataControllable?.delete(id: item.id)
            } catch {
                recordPersistenceFailure(error, operation: "ItemControllable.delete")
            }
            // An upsert queued while the delete above was suspended would recreate the row on
            // the next flush. See CODE_AUDIT_Folder §3.9.
            await dataControllable?.removePendingOperations(for: itemId)
        }
        if let fileUrlDataController, let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            if withFileData {
                fileUrlDataController.delete(fileUrl)
            }
        }

        itemDataModel.publishContentWidgetSnapshot()
    }
    
    @MainActor func isEqual(with other: ModelType) -> Bool {
        guard let other = other as? Model, let second = self.itemSync(for: other.id) else { return false }
        return second.isEqual(other: other)
    }
    
    @MainActor func replace(model: ModelType?, isInsert: Bool, forceSave: Bool = false) {
        replace(model: model, isInsert: isInsert, forceSave: forceSave, syncGameMemory: true)
    }

    /// - Parameter syncGameMemory: `false` leaves a loaded game-memory copy alone; the caller
    ///   mirrors only the fields it changed. Copying the whole library state into it would drop
    ///   that copy's session-only changes. See CODE_AUDIT_Folder §5.21, §5.23.
    @MainActor func replace(model: ModelType?, isInsert: Bool, forceSave: Bool, syncGameMemory: Bool) {
        guard let model = model as? Model else { return }
        if itemDataModel.isGameMode == true && forceSave == false {
            replaceInGameMemory(model: model)
            return
        }
        
        if let original = self.itemSync(for: model.id, noGame: true) {
            let resort = original.name != model.name
            if original.replace(with: model) {
                do {
                    try dataControllable?.replaceSync(id: original.id, with: original.copy())
                } catch {
                    recordPersistenceFailure(error, operation: "ItemControllable.replace")
                }
                if resort {
                    resortItem(changed: original)
                }
                itemDataModel.publishContentWidgetSnapshot()
            }
            if syncGameMemory {
                syncGameMemoryIfLoaded(with: original)
            }
        } else {
            if isInsert {
                do {
                    try dataControllable?.replaceSync(id: model.id, with: model.copy())
                    dataControllable?.markUnsavedInsert(id: model.id)
                } catch {
                    recordPersistenceFailure(error, operation: "ItemControllable.replace(insert)")
                }
            }
            resetModel(with: model)
            if syncGameMemory {
                syncGameMemoryIfLoaded(with: model)
            }
        }
    }

    /// Persists a game-memory item into the library. The sender's snapshot is merged with the
    /// library copy (or taken as sent, for an `authoritative` delivery such as the game
    /// master's map) and always keeps the local folder placement and visibility. Writing the
    /// raw snapshot lost local edits and moved the item to the sender's folder.
    /// See CODE_AUDIT_Folder §5.23.
    @MainActor func persistFromGame(model: ModelType, authoritative: Bool) {
        guard let model = model as? Model else { return }
        guard let library = itemSync(for: model.id, noGame: true) else {
            replace(model: model, isInsert: true, forceSave: true)
            return
        }
        var persisted: Model
        if authoritative {
            persisted = model.copy()
        } else {
            guard let merged = mergeSync(with: model, forceMerge: true, noGame: true) as? Model else { return }
            persisted = merged
        }
        persisted.parentId = library.parentId
        persisted.displayState = library.displayState
        // The game copy keeps what the game shows; only the library is written.
        replace(model: persisted, isInsert: true, forceSave: true, syncGameMemory: false)
    }

    /// Persists a folder or collection membership change made in the library UI, also during a
    /// running game, and mirrors only the membership fields into a loaded game-memory copy.
    /// See CODE_AUDIT_Folder §5.21.
    @MainActor func persistMembershipChange(model: ModelType) {
        guard let model = model as? Model else { return }
        replace(model: model, isInsert: false, forceSave: true, syncGameMemory: false)
        if var gameItem = itemDataModel.gameItemData[model.id] as? Model {
            if gameItem.parentId != model.parentId {
                gameItem.parentId = model.parentId
            }
            if model.specialCategory, gameItem.entries != model.entries {
                gameItem.entries = model.entries
            }
        }
    }

    /// Keeps a live game session's in-memory snapshot of this item consistent with
    /// a just-persisted write.
    ///
    /// `ItemDataModel.item(for:)` always prefers `gameItemData` over the permanent
    /// store whenever an entry exists there, regardless of `isGameMode` — so a
    /// `forceSave: true` edit (e.g. from the standalone item editor while a game is
    /// running) that only updated the permanent store would otherwise stay invisible
    /// to every reader — the editor's own re-render, the live game view, and any
    /// other view — for as long as this item remains loaded into game memory, and
    /// even after the game ends if `gameItemData` is never cleared for it.
    ///
    /// Mutates the existing game-memory instance in place (like the permanent-store
    /// branch above does via `original.replace(with: model)`) rather than replacing
    /// it with a fresh copy: any view or model already holding a reference to that
    /// exact `@Observable` instance — e.g. a live game view rendered from a
    /// different `SheetRootModel` — must see the change through its own reference,
    /// not just through a fresh dictionary lookup.
    @MainActor private func syncGameMemoryIfLoaded(with model: Model) {
        guard let gameItem = itemDataModel.gameItemData[model.id] as? Model else { return }
        _ = gameItem.replace(with: model)
    }

    /// Replaces an imported item and keeps the cross-module link register in sync with
    /// the imported value. Import paths bypass `EditControllable.saveChanges`, so they
    /// must use this method instead of plain `replace(model:isInsert:forceSave:)`.
    @MainActor func replaceImportedModel(model: ModelType?, isInsert: Bool, forceSave: Bool = false) {
        guard let model = model as? Model else { return }
        registerImportedLinks(of: model)
        replace(model: model, isInsert: isInsert, forceSave: forceSave)
    }

    /// `replaceImportedModel(model:isInsert:forceSave:)` with the destination decided by the
    /// caller instead of read from `isGameMode` at write time: an import captures it once when
    /// it starts, so a game ending mid-package cannot switch later items of the same package
    /// to the permanent library. See CODE_AUDIT_Folder §3.4.
    @MainActor func replaceImportedModel(model: ModelType?, isInsert: Bool, policy: GameMutationPolicy) {
        guard let model = model as? Model else { return }
        registerImportedLinks(of: model)
        replaceForGame(model: model, isInsert: isInsert, policy: policy)
    }

    @MainActor private func registerImportedLinks(of model: Model) {
        if let previous = itemSync(for: model.id)?.copy() {
            let changes = model.changedLinkRegisterModels(oldValue: previous)
            linkRegisterController.deregister(links: changes.removed)
            linkRegisterController.register(links: changes.added)
        } else {
            linkRegisterController.register(links: model.linkRegisterModels)
        }
    }

    /// The file references of every permanent-library item, except `excludedId`.
    @MainActor func libraryFileUrls(excluding excludedId: UUID? = nil) -> [FileUrl] {
        itemDataModel.items.compactMap { itemId in
            guard itemId != excludedId else { return nil }
            return itemSync(for: itemId, noGame: true)?.fileUrl
        }
    }

    /// After an import applied `itemId`, keeps whichever of the file it wrote and the item's
    /// previous file the library item references now, and removes the other one unless another
    /// item uses it. Imports used to leave the superseded file (or an unused new one) behind.
    /// See CODE_AUDIT_Folder §5.26.
    @MainActor internal func settleImportedFile(_ file: ImportedFileWrite, itemId: UUID) async {
        guard let controller = fileUrlDataController else { return }
        let current = itemSync(for: itemId, noGame: true)?.fileUrl
        let others = libraryFileUrls(excluding: itemId)
        func isUsedElsewhere(_ fileUrl: FileUrl) -> Bool {
            others.contains { controller.isSameStoredFile($0, fileUrl) }
        }
        if let current, controller.isSameStoredFile(current, file.written) {
            if let previous = file.previous, !controller.isSameStoredFile(previous, file.written), !isUsedElsewhere(previous) {
                await controller.deleteReplaced(previous, keeping: file.written)
            }
        } else if !isUsedElsewhere(file.written) {
            await controller.removeStoredFile(file.written)
        }
    }

    /// Merge keeps the local display state and folder placement, so an item in the local trash
    /// stayed there after re-importing a backup that has it, and was purged at the next launch.
    /// A visible imported copy restores it, with the backup's folder placement. Returns `merged`
    /// unchanged when there is nothing to restore. See CODE_AUDIT_Folder §5.20.
    @MainActor func restoringTrashedItem(merged: ModelType?, imported: ModelType) -> ModelType? {
        let trashed = DisplayStateMask.totalHidden.rawValue
        guard let imported = imported as? Model, imported.displayState != trashed,
              let local = itemSync(for: imported.id, noGame: true), local.displayState == trashed else { return merged }
        var restored = ((merged as? Model) ?? local).copy()
        restored.displayState = imported.displayState
        restored.parentId = imported.parentId
        return restored
    }

    /// An imported folder may be a partial copy: a subset export lists only the exported
    /// children. Overwriting the local folder with it dropped its other children, which then
    /// vanished from the folder list. The local children that still belong to the folder are
    /// kept. See CODE_AUDIT_Folder §5.8.
    @MainActor func keepingLocalFolderChildren(_ model: ModelType) -> ModelType {
        guard let imported = model as? Model, imported.isFolder,
              let local = itemSync(for: imported.id, noGame: true) else { return model }
        let localChildren = local.entries.filter { itemSync(for: $0.childId, noGame: true)?.parentId == local.id }
        guard !localChildren.isEmpty else { return model }
        let result = imported.copy()
        result.entries = FolderEntryMerge.merged(local: imported.entries, remote: localChildren, id: \.id, name: \.name, childId: \.childId)
        return result
    }

    /// Whether the permanent-library copy of `id` still equals `snapshot`; both absent counts as
    /// equal. Lets a caller that suspended after taking `snapshot` detect a write that landed in
    /// between. See CODE_AUDIT_Folder §3.6, §3.17.
    @MainActor func libraryModel(id: UUID, matches snapshot: (any ModelType)?) -> Bool {
        let current = itemSync(for: id, noGame: true)
        switch (current, snapshot) {
        case (nil, nil):
            return true
        case let (current?, snapshot?):
            guard let snapshot = snapshot as? Model else { return false }
            return current == snapshot
        default:
            return false
        }
    }

    /// Persists `fileUrl` on the permanent-library copy of `itemId` and mirrors only that field
    /// into a loaded game-memory copy. A whole-model `replace` would either be skipped (when
    /// handed the stored instance) or overwrite the game copy's session-only changes with the
    /// library state. See CODE_AUDIT_Folder §3.11.
    @MainActor func persistFileUrl(_ fileUrl: FileUrl, itemId: UUID) {
        if let library = itemSync(for: itemId, noGame: true), library.fileUrl != fileUrl {
            var updated = library.copy()
            updated.fileUrl = fileUrl
            if library.replace(with: updated) {
                do {
                    try dataControllable?.replaceSync(id: library.id, with: library.copy())
                } catch {
                    recordPersistenceFailure(error, operation: "ItemControllable.persistFileUrl")
                }
            }
        }
        if var gameItem = itemDataModel.gameItemData[itemId] as? Model, gameItem.fileUrl != fileUrl {
            gameItem.fileUrl = fileUrl
        }
    }

    /// Stages one exact model snapshot for an external-import transaction and
    /// surfaces persistence errors to the caller. This deliberately does not
    /// change the best-effort behaviour of the general editor API above.
    @MainActor func replaceForExternalImport(
        model: any ModelType,
        isInsert: Bool
    ) throws {
        guard let model = model as? Model else {
            throw ItemTransactionMutationError.incompatibleModel
        }

        let snapshot = model.copy()
        let existing = itemSync(for: snapshot.id, noGame: true)
        if existing != nil || isInsert {
            try dataControllable?.replaceSync(id: snapshot.id, with: snapshot)
            if existing == nil {
                dataControllable?.markUnsavedInsert(id: snapshot.id)
            }
        }

        if let existing {
            let needsResort = existing.name != snapshot.name
            setModel(with: snapshot)
            if needsResort {
                resortItem(changed: snapshot)
            }
        } else {
            resetModel(with: snapshot)
        }
    }

    /// Removes an item as part of external-import rollback while keeping the
    /// binary intact. Database staging happens before the in-memory removal so a
    /// thrown error never masquerades as a successful rollback.
    @MainActor func deleteForExternalImport(itemId: UUID) async throws {
        guard let item = itemSync(for: itemId, noGame: true) else { return }
        // A failed consolidated save re-queues the import's own insert; drop it, or the
        // rollback's second save commits the item the import just rolled back.
        // See CODE_AUDIT_19 §5.1.
        await dataControllable?.removePendingOperations(for: item.id)
        try await dataControllable?.delete(id: item.id)

        for entry in item.entries {
            await cacheControllable?.remove(itemId: entry.id)
        }
        if let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            fileUrlDataController?.removeBookmarks(fileId: fileUrl.fileId)
        }
        itemDataModel.resetModel(id: item.id)
    }

    /// Exact copies of the current library models used to cover repair effects
    /// that can reach parents or children outside the selected import batch.
    @MainActor func externalImportSnapshots(ids: Set<UUID>) -> [UUID: any ModelType] {
        ids.reduce(into: [:]) { snapshots, itemId in
            if let item = itemSync(for: itemId, noGame: true) {
                snapshots[itemId] = item.copy()
            }
        }
    }

    /// The items outside `importedIds` that the import repair (`ConvertController`) can change:
    /// the folder parent each imported item may be removed from, and the entry children whose
    /// display state an un-grouping resets. Snapshotting only these keeps a rollback from
    /// reverting unrelated items of the module. See CODE_AUDIT_Folder §3.6.
    @MainActor func externalImportRepairScope(importedIds: Set<UUID>) -> Set<UUID> {
        var scope: Set<UUID> = []
        for itemId in importedIds {
            guard let item = itemSync(for: itemId, noGame: true) else { continue }
            if let parentId = item.parentId {
                scope.insert(parentId)
            }
            scope.formUnion(item.entries.map(\.childId))
        }
        return scope.subtracting(importedIds).filter { itemSync(for: $0, noGame: true) != nil }
    }

    @MainActor func replaceForGame(model: ModelType?, isInsert: Bool, policy: GameMutationPolicy) {
        switch policy {
        case .memoryOnly:
            replaceInGameMemory(model: model)
        case .persist:
            replace(model: model, isInsert: isInsert, forceSave: true)
        }
    }

    /// Mutates the existing game-memory instance in place when this item is
    /// already loaded (preserving its object identity, like
    /// `syncGameMemoryIfLoaded` above does for the reverse direction) rather
    /// than replacing it with the incoming reference: any view or model
    /// already holding a reference to that exact `@Observable` instance must
    /// see the change through its own reference, not just through a fresh
    /// dictionary lookup.
    @MainActor func replaceInGameMemory(model: ModelType?) {
        guard let model = model as? Model else { return }
        if let existing = itemDataModel.gameItemData[model.id] as? Model {
            _ = existing.replace(with: model)
        } else {
            itemDataModel.gameItemData[model.id] = model
        }
    }

    /// Applies a synced copy of an existing item. The image cache for a changed file is dropped
    /// before the model changes, so a view re-rendering from the new model never reads the old
    /// cached bytes. See CODE_AUDIT_Folder §3.19.
    @MainActor func mergeUpdates(model: ModelType) async {
        await invalidateCacheForChangedFile(of: model)
        applyMergedUpdate(model: model)
    }

    /// Drops the image cache of the stored item when `model` carries a different file.
    @MainActor func invalidateCacheForChangedFile(of model: ModelType) async {
        guard let model = model as? Model,
              let original = itemSync(for: model.id, noGame: true),
              original.fileUrl?.contentHash != model.fileUrl?.contentHash else { return }
        await cacheControllable?.remove(itemId: original.id)
    }

    /// The synchronous part of `mergeUpdates(model:)`; the caller drops the cache first.
    @MainActor func applyMergedUpdate(model: ModelType) {
        guard let model = model as? Model, let original = self.itemSync(for: model.id, noGame: true) else { return }
        let resort = original.name != model.name
        // Re-derive the in-memory link register from the merged value, mirroring
        // `replaceImportedModel`'s pattern. Without this, a CloudKit-synced merge
        // (this method, called from `SyncDataControllable.updateFromSync`) never
        // touched the link register at all, so links added or changed on another
        // device stayed invisible to "used by" lookups on this device until the
        // user happened to re-save the item locally. See CODE_AUDIT_17 §5.9.
        let previous = original.copy()
        if original.replace(with: model) {
            let changes = original.changedLinkRegisterModels(oldValue: previous)
            linkRegisterController.deregister(links: changes.removed)
            linkRegisterController.register(links: changes.added)
            // Another device's replacement of this item's file (same id, new content hash)
            // used to leave the image cache serving the stale bytes; `mergeUpdates` drops it
            // before this runs. See CODE_AUDIT_17 §5.13, CODE_AUDIT_Folder §3.19.
            if resort {
                resortItem(changed: original)
            }
            itemDataModel.publishContentWidgetSnapshot()
        }
    }
}

// MARK: - Intern

// Internal, not private: ItemControllable+Sync.swift uses these too. See CODE_AUDIT_19 §9.23.
extension ItemControllable {
    @MainActor func setModel(with model: Model) {
        itemDataModel.setItem(id: model.id, item: model)
    }

    @MainActor func resortItem(changed model: Model) {
        guard itemDataModel.removeItem(itemId: model.id) else { return }
        insertIntoItems(model: model)
    }

    @MainActor func insertIntoItems(model: Model) {
        // `itemDataModel.items` is maintained in sorted-by-name order, so the insertion
        // point can be found with a binary search instead of a full linear scan that
        // did a dictionary lookup + string comparison per existing item on every edit
        // that changes an item's name, in every module. See CODE_AUDIT_EditItem §7.1.
        var low = 0
        var high = itemDataModel.items.count
        while low < high {
            let mid = (low + high) / 2
            let midName = itemSync(for: itemDataModel.items[mid], noGame: true)?.name ?? ""
            if midName.localizedCompare(model.name) == .orderedDescending {
                high = mid
            } else {
                low = mid + 1
            }
        }
        itemDataModel.insert(itemId: model.id, at: low == itemDataModel.items.count ? nil : low)
    }
}
