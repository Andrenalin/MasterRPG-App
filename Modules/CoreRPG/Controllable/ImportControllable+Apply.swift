// @copyright André Trettin

import Foundation
import os.log
import Observation

// Applying an imported item, split out of ImportControllable.swift. See CODE_AUDIT_29 §9.9.

extension ImportControllable {
    /// Captures, once per module stream, where its items go. Reading `isGameMode` separately at
    /// every step let a game that ended mid-package send later items of the same package to the
    /// permanent library. See CODE_AUDIT_Folder §3.4.
    @MainActor
    func applyPolicy(importModel: ItemDataImportModel, forceSave: Bool, gameMemoryOnly: Bool) -> ImportApplyPolicy {
        ImportApplyPolicy(
            mode: importModel.importMode,
            forceSave: forceSave,
            gameMemoryOnly: gameMemoryOnly,
            writesGameMemory: !forceSave && itemControllable.itemDataModel.isGameMode,
            isUntrustedSource: importModel.isUntrustedSource
        )
    }

    /// Normalises, merges and writes one decoded item in a single main-actor step, so no sync or
    /// user edit can land between the merge and the write and be overwritten by the stale merge
    /// result. See CODE_AUDIT_Folder §3.4. Returns whether the item was written to a module list
    /// whose folders `repairFolders` must then check; the caller repairs once per batch.
    /// See CODE_AUDIT_Folder §7.3.
    @discardableResult @MainActor
    func applyImportedItem(_ importedItem: ModelType, id: UUID, policy: ImportApplyPolicy, importModel: ItemDataImportModel, locallyReusedFileIds: Set<UUID>) -> Bool {
        let itemController = itemControllable
        // A memory-only game delivery whose game has ended since the package started has no
        // game memory left to go to, and must not fall through to the library.
        guard !policy.writesGameMemory || itemController.itemDataModel.isGameMode else {
            Logger.importController.info("Import dropped an item of a game package that arrived after the game ended module=\(itemController.config.module.rawValue, privacy: .public)")
            importModel.importedItems += 1
            return false
        }
        let normalizedImportedItem = itemController.normalizedImportedItem(from: importedItem)
        guard let importableItem = itemController.gameModeImportedItem(from: normalizedImportedItem, writesGameMemory: policy.writesGameMemory, locallyReusedFileIds: locallyReusedFileIds) else {
            importModel.importedItems += 1
            return false
        }

        // A saved-game load never touches the permanent library — write straight into this
        // module's game memory regardless of merge/overwrite mode or isGameMode.
        // `replaceForGame(policy: .memoryOnly)` only fills the game-shadow dictionary
        // (`gameItemData`); nothing considers the item "in the running game" — `gameItems`
        // stays the authority for that (see `ItemGameModel.currentItemId`/`.items`) — until it's
        // in that id list too, so add it there ourselves.
        guard !policy.gameMemoryOnly else {
            replaceForGameAndCount(importableItem, id: id, itemController: itemController, importModel: importModel)
            importModel.recordApplied(id, module: itemController.config.module)
            return false
        }

        let writePolicy: GameMutationPolicy = policy.writesGameMemory ? .memoryOnly : .persist
        var needsFolderRepair = false
        switch policy.mode {
        case .merge:
            let groupsBefore = groupItemIdsBeforeImport(id: id, policy: policy)
            var finalItem = itemController.mergeSync(with: importableItem, forceMerge: !policy.writesGameMemory)
            if !policy.writesGameMemory {
                let merged = finalItem
                finalItem = itemController.restoringTrashedItem(merged: merged, imported: importableItem)
                if let restored = finalItem as? any ItemDataAccessible, !restored.isHidden,
                   itemController.itemSync(for: id, noGame: true)?.isHidden == true {
                    // Trashing gave the tags back; restoring takes them again.
                    editControllable.tagController.add(tags: restored.tags, module: itemController.config.module)
                }
            }
            if let finalItem {
                itemController.replaceImportedModel(model: finalItem, isInsert: true, policy: writePolicy)
                recordStaleGroups(before: groupsBefore, after: finalItem, ownerId: id, importModel: importModel)
                needsFolderRepair = true
                importModel.recordApplied(id, module: itemController.config.module)
            }

        case .overwrite:
            let groupsBefore = groupItemIdsBeforeImport(id: id, policy: policy)
            let finalItem = policy.writesGameMemory ? importableItem : itemController.keepingLocalFolderChildren(importableItem)
            itemController.replaceImportedModel(model: finalItem, isInsert: true, policy: writePolicy)
            recordStaleGroups(before: groupsBefore, after: finalItem, ownerId: id, importModel: importModel)
            needsFolderRepair = true
            importModel.recordApplied(id, module: itemController.config.module)

        case .manual:
            var merged = itemController.mergeSync(with: importableItem, forceMerge: !policy.writesGameMemory)
            if !policy.writesGameMemory {
                // The restore rule of the merge branch: a local item in the trash that the
                // backup has is offered restored. Without it an otherwise equal item was
                // skipped as unchanged, a different one kept its trashed state by default, and
                // both were purged at the next launch. Opening a backup file starts in manual
                // mode. See CODE_AUDIT_Folder §5.20, CODE_AUDIT_21 §5.30.
                merged = itemController.restoringTrashedItem(merged: merged, imported: importableItem)
            }
            recordManualReview(importableItem: importableItem, merged: merged as? any ItemDataAccessible, id: id, itemController: itemController, importModel: importModel)
        }

        importModel.importedItems += 1
        return needsFolderRepair
    }

    /// The groups the library item `id` has right now. Empty for a game-memory delivery: it never
    /// touches the library, so it must not remove a library group either.
    @MainActor
    private func groupItemIdsBeforeImport(id: UUID, policy: ImportApplyPolicy) -> Set<UUID> {
        guard !policy.writesGameMemory,
              let existing = itemControllable.itemSync(for: id, noGame: true) else { return [] }
        return editControllable.groupItemIds(of: existing)
    }

    /// Remembers the groups the written item `after` dropped, so `removeStaleGroups` deletes them.
    @MainActor
    private func recordStaleGroups(before: Set<UUID>, after: ModelType, ownerId: UUID, importModel: ItemDataImportModel) {
        guard !before.isEmpty, let after = after as? any ItemDataAccessible else { return }
        for groupId in before.subtracting(editControllable.groupItemIds(of: after)) {
            importModel.staleGroupOwners[groupId] = ownerId
        }
    }

    /// Deletes the groups newer imported items no longer reference. The merged entry is plain, so
    /// the group item would stay behind hidden and unreachable.
    @MainActor
    func removeStaleGroups(importModel: ItemDataImportModel) async {
        let groupOwners = importModel.staleGroupOwners
        guard !groupOwners.isEmpty else { return }
        importModel.staleGroupOwners = [:]
        await editControllable.removeStaleGroups(groupOwners)
    }

    @MainActor
    func repairFolders(_ itemIds: Set<UUID>) {
        guard !itemIds.isEmpty else { return }
        editControllable.repairFolders(itemIds: itemIds)
    }

    /// Cleans up after a file the import wrote for `itemId`. A library import keeps the file the
    /// item references now and removes the other; files of game-memory items are removed at game
    /// end, and files of a manual review once the review is applied or cancelled.
    /// See CODE_AUDIT_Folder §5.2, §5.26.
    @MainActor
    func settleImportedFile(_ fileWrite: ImportedFileWrite, itemId: UUID, policy: ImportApplyPolicy, importModel: ItemDataImportModel) async {
        if policy.gameMemoryOnly || policy.writesGameMemory {
            itemControllable.fileUrlDataController?.model.gameMemoryFiles.append(fileWrite.written)
        } else if policy.mode == .manual {
            importModel.reviewFileWrites.append((itemControllable.config.module, itemId, fileWrite))
        } else {
            await itemControllable.settleImportedFile(fileWrite, itemId: itemId)
        }
    }

    /// Runs the post-import folder and orphan repair for `importedIds`. In an unstructured task:
    /// the repair stops at `Task.isCancelled`, and after a cancelled import it must still run
    /// for the items already applied. See CODE_AUDIT_Folder §3.3.
    func repairImportedItems(_ importedIds: Set<UUID>) async {
        guard !importedIds.isEmpty else { return }
        let itemController = itemControllable
        let editController = editControllable
        await Task { @MainActor in
            let repair = ConvertController(itemController: itemController, editController: editController)
            await repair.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: importedIds)
        }.value
    }

    @MainActor
    private func replaceForGameAndCount(
        _ importableItem: ModelType,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        itemController.replaceForGame(model: importableItem, isInsert: true, policy: .memoryOnly)
        if !itemController.itemDataModel.isGameMode {
            itemController.itemDataModel.isSavedGameStaged = true
        }
        if !itemController.itemDataModel.gameItems.contains(id) {
            itemController.itemDataModel.gameItems.insert(id, at: 0)
        }
        importModel.importedItems += 1
    }

    @MainActor
    private func recordManualReview(
        importableItem: ModelType,
        merged: (any ItemDataAccessible)?,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        guard let imported = importableItem as? any ItemDataAccessible else { return }
        // A copy, not the live item: applying the review compares it with the library item to
        // detect a change made while the review sheet was open. See CODE_AUDIT_Folder §3.17.
        let existing: (any ItemDataAccessible)? = itemController.itemSync(for: id, noGame: true)?.copy()
        let module = itemController.config.module

        if existing != nil && merged == nil {
            logManualReviewUnchangedSkipped(module: module, id: id, imported: imported)
            return
        }

        let kind: ImportReviewItemModel.ChangeKind = existing == nil ? .added : .different
        let reviewItem = SingleReviewItem(existing: existing, imported: imported, merged: merged ?? imported)
        let itemModel = SingleItemImportModel.from(item: reviewItem)
        if kind == .different {
            logManualReviewDifference(
                module: module,
                id: id,
                existing: existing,
                imported: imported,
                itemModel: itemModel
            )
        }
        let reviewItemModel = ImportReviewItemModel(
            id: id,
            kind: kind,
            itemModel: itemModel
        )
        importModel.pendingModules[module, default: []].append(reviewItemModel)
    }
}
