// @copyright André Trettin

import Foundation
import Observation
import os.log

// Split out of ItemControllable.swift — see CODE_AUDIT_19 §9.23.

// MARK: - ImportControllable

public extension ItemControllable {
    @MainActor func decode(data: Data, with decoder: JSONDecoder, version: Int) throws -> Model {
        // default ignore any version numbers. Later a module can handle older version differently.
        try decoder.decode(Model.self, from: data)
    }

    @MainActor func merge(with model: ModelType, forceMerge: Bool = false) async -> ModelType? {
        mergeSync(with: model, forceMerge: forceMerge)
    }

    /// `merge(with:forceMerge:)` without a suspension point, so a caller can merge against the
    /// current item and write the result in one main-actor step. `noGame` merges against the
    /// permanent-library copy instead of a loaded game-memory copy. See CODE_AUDIT_Folder §3.4.
    @MainActor func mergeSync(with model: ModelType, forceMerge: Bool = false, noGame: Bool = false) -> ModelType? {
        guard forceMerge == true || itemDataModel.isGameMode == false else { return model }
        guard let model = model as? Model, let current = itemSync(for: model.id, noGame: noGame) else { return model }
        if model.isSame(current) {
            return nil
        }
        return model.merge(current)
    }
    
    @MainActor func reset(fileUrl: FileUrl?, item: inout any ItemDataAccessible) async {
        if let oldFileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: oldFileUrl.fileId)
        }
        item.fileUrl = fileUrl
    }
}

// MARK: - SyncDataController

public extension ItemControllable {
    @MainActor func resetData() async {
        // A sync batch queued before the reset must not re-insert or merge into the emptied
        // module afterwards. See CODE_AUDIT_Folder §3.19.
        itemDataModel.discardQueuedSyncBatches()
        let allItemIds = itemDataModel.items

        // Clean up cache and internal state for each item
        for id in allItemIds {
            guard let item = await self.item(for: id) else { continue }

            // Remove cache for all entries
            let entries = item.entries
            for entry in entries {
                await cacheControllable?.remove(itemId: entry.id)
            }

            // Will not remove files on reset Database
            // Remove file cache if exists
            if let fileUrl = item.fileUrl {
                await cacheControllable?.remove(itemId: id)
                fileUrlDataController?.removeBookmarks(fileId: fileUrl.fileId)
            }

            // Reset internal state
            itemDataModel.resetModel(id: item.id)
        }
        itemDataModel.publishContentWidgetSnapshot()

        // Batch delete all items from Core Data for better performance
        do {
            try await dataControllable?.batchDelete(ids: allItemIds)
            itemDataModel.lastPersistenceError = nil
        } catch {
            Logger.itemController.error("resetData() batch delete failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordSaveError(error)
        }
    }

    @MainActor func save() async {
        do {
            try await dataControllable?.save()
            itemDataModel.lastPersistenceError = nil
        } catch {
            // The in-memory edit already applied, so a failed save here leaves the UI
            // showing a change that never reached disk — log and surface it rather than
            // silently discarding the failure. See CODE_AUDIT §5.1, CODE_AUDIT_19 §5.13.
            Logger.itemController.error("save() failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordSaveError(error)
        }
        AppIntentContentInvalidator.invalidate()
    }

    /// A successful flush commits nothing, so it leaves an earlier save error in place; the
    /// banner's save error is cleared by `ContextFlushLedger` when a save commits.
    /// See CODE_AUDIT_19 §5.13, CODE_AUDIT_20 §5.11.
    @MainActor func flushPendingOperations() async {
        do {
            try await dataControllable?.flushPendingOperations()
        } catch {
            Logger.itemController.error("flushPendingOperations() failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            itemDataModel.lastPersistenceError = error
            PersistenceIssueCenter.shared.recordSaveError(error)
        }
    }

    /// - Parameter unsavedBeforeFetch: the unsaved-insert ids read before `models` was fetched.
    ///   An insert that commits while the fetch runs is in neither the fetch nor a later read of
    ///   the unsaved ids, so both reads are combined. See CODE_AUDIT_Folder §3.10.
    @MainActor func updates(_ models: [ModelType], unsavedBeforeFetch: Set<UUID> = []) async {
        let sortedModels = models.compactMap { $0 as? Model }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        // O(n) set membership instead of an O(n·m) nested `.contains` scan — this runs on
        // every full CloudKit sync reconciliation. See CODE_AUDIT_EditItem §7.1.
        let sortedModelIds = Set(sortedModels.map(\.id))
        // The ids known before the first suspension: an item added while this reconciliation
        // awaits is in neither the fetch nor the unsaved ids read below. See CODE_AUDIT_26 §5.49.
        let idsBeforeAwait = Set(itemDataModel.items)
        // Locally created items whose insert is still queued are not in the store yet; they
        // are not deletions. See CODE_AUDIT_18 §5.2.
        let unsavedInsertIds = unsavedBeforeFetch.union(await dataControllable?.unsavedInsertIds() ?? [])
        // An id that appeared during the await is a new local item, not a deletion.
        let deletedIds = itemDataModel.items.filter {
            !sortedModelIds.contains($0) && !unsavedInsertIds.contains($0) && idsBeforeAwait.contains($0)
        }
        for id in deletedIds {
            // Full-table reconciliation (a store swap, or the once-at-launch initial
            // fetch) must stay memory-only, matching `updateFromSync`'s incremental
            // deletion path: an id missing from the freshly fetched list may just be
            // an in-memory id from the old store, not a real deletion, so this must
            // never touch the binary file or issue a database delete. See
            // CODE_AUDIT_17 §5.1.
            await delete(itemId: id, withFileData: false, withDatabase: false)
        }
        // A reconciliation that runs mid-session (after a failed id or item fetch) must not
        // replace the live instance of an item that is already loaded: open views and editors
        // hold it, and an edit queued but not flushed would be reverted in memory. Known ids are
        // merged like an incremental sync update; only new ids get a new instance.
        // See CODE_AUDIT_20 §5.6.
        // Changed files drop their image cache first, while nothing below has run yet: the
        // apply loop must not suspend, or a concurrent insert could be lost by `resetItems`.
        // See CODE_AUDIT_Folder §3.19.
        for item in sortedModels where itemSync(for: item.id, noGame: true) != nil {
            await invalidateCacheForChangedFile(of: item)
        }
        let knownIds = Set(itemDataModel.items)
        var updatedItems: [UUID] = []
        for item in sortedModels {
            if knownIds.contains(item.id), itemSync(for: item.id, noGame: true) != nil {
                applyMergedUpdate(model: item)
            } else {
                setModel(with: item)
                healDuplicateFolderMembers(itemId: item.id)
            }
            updatedItems.append(item.id)
        }
        // Unsaved local inserts are kept in `itemData` above; keep them listed too, or they
        // vanish from lists, exports and link lookups until relaunch. See CODE_AUDIT_19 §5.12.
        updatedItems += itemDataModel.items.filter {
            !sortedModelIds.contains($0) && (unsavedInsertIds.contains($0) || !idsBeforeAwait.contains($0))
        }
        itemDataModel.resetItems(updatedItems)
        itemDataModel.publishContentWidgetSnapshot()
        // The initial load and a reconciliation change items without a save. See CODE_AUDIT_AppIntents §7.1.
        AppIntentContentInvalidator.invalidate()
    }
    
    @MainActor func resetModel(with model: ModelType?) {
        guard let model = model as? Model else { return }
        setModel(with: model)
        insertIntoItems(model: model)
        itemDataModel.publishContentWidgetSnapshot()
    }
}
