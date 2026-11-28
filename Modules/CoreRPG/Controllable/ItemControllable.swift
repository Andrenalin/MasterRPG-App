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
        itemDataModel.items.compactMap { itemId -> Model? in
            guard let item = itemSync(for: itemId), isMoveTarget(item, isFolder: isFolder, in: parentId) else { return nil }
            return item
        }
    }

    /// Whether `collections(isFolder:in:)` would return anything, stopping at the first match:
    /// the Move/Add commands only need this to enable themselves, on every body evaluation.
    /// See CODE_AUDIT_Folder §7.4.
    @MainActor func hasCollections(isFolder: Bool, in parentId: UUID?) -> Bool {
        itemDataModel.items.contains { itemId in
            itemSync(for: itemId).map { isMoveTarget($0, isFolder: isFolder, in: parentId) } ?? false
        }
    }

    @MainActor private func isMoveTarget(_ item: Model, isFolder: Bool, in parentId: UUID?) -> Bool {
        item.displayState == DisplayStateMask.fullVisible.rawValue
            && item.parentId == parentId
            && item.category == (isFolder ? .folder : collectionCategory)
    }
}

// MARK: - EditControllable

public extension ItemControllable {
    /// Creates an empty item of `type` in the library, also during a game: the user's "Add Item"
    /// (and every test fixture). An item created as part of another edit takes that edit's
    /// policy with `addNew(type:forceSave:)`.
    @MainActor func addNew(type: ItemListCategory) async -> UUID {
        await addNew(type: type, forceSave: true)
    }

    /// Creates an empty item of `type`. - Parameter forceSave: see `insertNew(model:forceSave:)`.
    @MainActor func addNew(type: ItemListCategory, forceSave: Bool) async -> UUID {
        var model = Model.empty.copy()
        model.category = type
        await insertNew(model: model, forceSave: forceSave)
        return model.id
    }

    /// Inserts the new item `model` once, complete, with the caller's write policy: during a game
    /// a memory-only create stays in game memory. `addNew` always wrote an empty item to the
    /// store while the caller filled it memory-only, which left empty, nameless items in the
    /// library. See CODE_AUDIT_Edit_Save §5.9.
    @MainActor func insertNew(model: ModelType, forceSave: Bool) async {
        guard let model = model as? Model else { return }
        if itemDataModel.isGameMode && !forceSave {
            replaceInGameMemory(model: model)
            return
        }
        CloudKitOperationCounter.shared.recordOperation(function: "ItemControllable.insertNew(category:\(model.category))")
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
    }

    @MainActor func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }
    
    /// Works on the library item: its row, its file, and on a failed delete the instance put
    /// back. The game copy's file was deleted instead (a delivered newer file), orphaning the
    /// library file, and a failure made session state the library object. A file only the game
    /// copy names is a game file, removed at game end (`removeUnreferencedGameFiles`). An item
    /// only game memory holds is deleted as that copy. See CODE_AUDIT_Edit_Save §5.25.
    @MainActor func delete(itemId: UUID, withFileData: Bool = true, withDatabase: Bool = true) async {
        guard let item = itemSync(for: itemId, noGame: true) ?? itemSync(for: itemId) else { return }

        // Leave memory before the first suspension: from here on no editor, import or sync
        // can find the item and queue a fresh upsert for it while the deletion below awaits.
        // Removing it last left that window open for the whole delete. See CODE_AUDIT_Folder §3.9.
        itemDataModel.resetModel(id: item.id)
        if config.module == .value {
            UserDefaultsQuickDiceSlotStore.forget(characterId: itemId)
        }
        // Until this delete is through, sync does not bring the id back. See CODE_AUDIT_21 §5.31.
        itemDataModel.deletingIds.insert(itemId)
        defer { itemDataModel.deletingIds.remove(itemId) }
        // In the same step: the file is unreferenced from here on but only deleted at the end,
        // after the suspensions below. An import in between reused it, and the deletion then
        // removed it under the imported item. See CODE_AUDIT_21 §3.6.
        let announcedFileDeletion = withFileData ? fileUrlDataController?.announceDeletion(of: item.fileUrl) : nil

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
            CloudKitOperationCounter.shared.recordOperation(function: "ItemControllable.delete(itemId:withFileData:\(withFileData))")
            do {
                try await dataControllable?.delete(id: item.id)
            } catch {
                recordPersistenceFailure(error, operation: "ItemControllable.delete")
                // The row survives on disk and in CloudKit and comes back at the next launch or
                // sync, so its file must stay and the item stays usable. See CODE_AUDIT_23 §5.6.
                announcedFileDeletion?.withdraw()
                // The failed flush put the deletion back in the queue: the next save would
                // remove the row the item was just restored for. See CODE_AUDIT_28 §5.5.
                await dataControllable?.removePendingOperations(for: itemId)
                resetModel(with: item)
                return
            }
            // An upsert queued while the delete above was suspended would recreate the row on
            // the next flush. See CODE_AUDIT_Folder §3.9.
            await dataControllable?.removePendingOperations(for: itemId)
        }
        if let fileUrlDataController, let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            if withFileData {
                // Two items can reference one stored file; it goes with its last item only.
                // See CODE_AUDIT_21 §5.2.
                let keepsStoredFile = isFileUsedElsewhere(fileUrl, excluding: itemId)
                Logger.fileStore.notice("delete item file: location \(String(describing: fileUrl.location), privacy: .public) name \(fileUrl.rawUrl.lastPathComponent, privacy: .private) shared \(keepsStoredFile, privacy: .public) announced \(announcedFileDeletion != nil, privacy: .public)")
                fileUrlDataController.delete(
                    fileUrl,
                    keepingStoredFile: keepsStoredFile,
                    announced: announcedFileDeletion
                )
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
        guard let sessionModel = model as? Model else { return }
        if itemDataModel.isGameMode == true && forceSave == false {
            replaceInGameMemory(model: sessionModel)
            return
        }
        
        // What the library keeps: the model without the game's session-only content. The game
        // copy is mirrored from the unfiltered model below.
        let sanitized = itemDataModel.isGameMode ? itemDataModel.libraryWriteFilter?(sessionModel) as? Model : nil
        let model = sanitized ?? sessionModel

        if let original = self.itemSync(for: model.id, noGame: true) {
            let resort = original.name != model.name
            if original.replace(with: model) {
                itemDataModel.markIndexDirty(original.id)
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
                syncGameMemoryIfLoaded(with: sanitized == nil ? original : sessionModel)
            }
        } else {
            // Also when the caller did not ask for an insert: an id that is not in the library
            // was added to memory without a database write, so the item was in every list
            // until the next launch and then gone. See CODE_AUDIT_21 §5.16.
            do {
                try dataControllable?.replaceSync(id: model.id, with: model.copy())
                dataControllable?.markUnsavedInsert(id: model.id)
            } catch {
                recordPersistenceFailure(error, operation: isInsert ? "ItemControllable.replace(insert)" : "ItemControllable.replace(new id)")
            }
            resetModel(with: model)
            if syncGameMemory {
                syncGameMemoryIfLoaded(with: sessionModel)
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
        if forceSave || !itemDataModel.isGameMode {
            registerImportedLinks(of: model)
        }
        replace(model: model, isInsert: isInsert, forceSave: forceSave)
    }

    /// `replaceImportedModel(model:isInsert:forceSave:)` with the destination decided by the
    /// caller instead of read from `isGameMode` at write time: an import captures it once when
    /// it starts, so a game ending mid-package cannot switch later items of the same package
    /// to the permanent library. See CODE_AUDIT_Folder §3.4.
    @MainActor func replaceImportedModel(model: ModelType?, isInsert: Bool, policy: GameMutationPolicy) {
        guard let model = model as? Model else { return }
        // A game delivery stays in game memory, and so do its links: the persistent register
        // lists only what the library holds. See CODE_AUDIT_Edit_Save §5.27.
        if policy == .persist {
            registerImportedLinks(of: model)
        }
        replaceForGame(model: model, isInsert: isInsert, policy: policy)
    }

    /// Diffs against the library item, which the register describes; the game copy carried
    /// session links into the register and missed links only the library had.
    /// See CODE_AUDIT_Edit_Save §5.21.
    @MainActor private func registerImportedLinks(of model: Model) {
        if let previous = itemSync(for: model.id, noGame: true)?.copy() {
            let changes = model.changedLinkRegisterModels(oldValue: previous)
            linkRegisterController.deregister(links: changes.removed)
            linkRegisterController.register(links: changes.added)
        } else {
            linkRegisterController.register(links: model.linkRegisterModels)
        }
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
        // An entry that is (still) the library instance is replaced, not mutated, so a
        // memory-only edit never changes the library object. See CODE_AUDIT_29 §5.1.
        if let existing = itemDataModel.gameItemData[model.id] as? Model,
           !isLibraryInstance(existing) {
            _ = existing.replace(with: model)
        } else {
            itemDataModel.gameItemData[model.id] = model
        }
    }

    /// Whether `model` is the very object the library keeps for its id.
    @MainActor func isLibraryInstance(_ model: Model) -> Bool {
        guard let library = itemDataModel.itemData[model.id] else { return false }
        return (library as AnyObject) === (model as AnyObject)
    }

    /// Applies a synced copy of an existing item. The image cache for a changed file is dropped
    /// before the model changes, so a view re-rendering from the new model never reads the old
    /// cached bytes. See CODE_AUDIT_Folder §3.19.
    ///
    /// `keepingLocalEdit`: this device has an edit of the item queued but not committed. The
    /// store row predates it, so it is CRDT-merged with the in-memory item instead of replacing
    /// it, and the merged value is queued after the local edit. Replacing it dropped the local
    /// edit from the UI, and the flush then wrote the stale snapshot over the remote change.
    /// See CODE_AUDIT_Edit_Save §3.1.
    @MainActor func mergeUpdates(model: ModelType, keepingLocalEdit: Bool = false) async {
        await invalidateCacheForChangedFile(of: model)
        guard keepingLocalEdit, let fetched = model as? Model,
              let current = itemSync(for: fetched.id, noGame: true) else {
            applyMergedUpdate(model: model)
            return
        }
        let merged = fetched.merge(current)
        applyMergedUpdate(model: merged)
        do {
            try dataControllable?.replaceSync(id: merged.id, with: merged)
        } catch {
            recordPersistenceFailure(error, operation: "ItemControllable.mergeUpdates(keepingLocalEdit:)")
        }
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
            itemDataModel.markIndexDirty(original.id)
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
        healDuplicateFolderMembers(itemId: original.id)
    }

    /// Lists every member of the library folder `itemId` once and writes the result back, which
    /// also removes the surplus rows from the database and the other devices. A folder loaded
    /// or synced with two entries for one member (see `FolderEntryMerge.deduplicated`) showed
    /// the member twice in the folder's own entries. Returns whether a duplicate was removed.
    @MainActor @discardableResult func healDuplicateFolderMembers(itemId: UUID) -> Bool {
        guard let item = itemSync(for: itemId, noGame: true), item.isFolder,
              let unique = FolderEntryMerge.deduplicated(item.entries, id: \.id, childId: \.childId) else { return false }
        item.entries = unique
        itemDataModel.markIndexDirty(itemId)
        do {
            try dataControllable?.replaceSync(id: itemId, with: item.copy())
        } catch {
            recordPersistenceFailure(error, operation: "ItemControllable.healDuplicateFolderMembers")
        }
        return true
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
