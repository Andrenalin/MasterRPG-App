// @copyright André Trettin

import SwiftUI
import os.log

// MARK: - Collect Items for Removal

public extension EditControllable {
    /// The items a delete of `items` removes: `items` and, for a folder, everything below it.
    /// Nothing is changed here. The delete panel lists the result and `confirmRemoval` trashes
    /// it on Remove; trashing it before the panel opened let the launch cleanup purge items the
    /// user never confirmed when the app was terminated with the panel open.
    /// See CODE_AUDIT_21 §5.29.
    @MainActor func collectionItemsForRemoval(for items: [ItemRowModel]) -> [ItemRowModel] {
        var allRemovingItems = items
        var processedIds = Set<UUID>()

        func collectChildren(from itemModels: [ItemRowModel]) {
            for itemModel in itemModels {
                guard !processedIds.contains(itemModel.itemId) else { continue }
                processedIds.insert(itemModel.itemId)

                if let model = itemControllable.itemSync(for: itemModel.itemId), model.isFolder {
                    // Only folders delete their children, so only add folder children to the removing list
                    // An entry left behind by a move, a CloudKit merge or an import can name an
                    // item that lives in another folder now; only a child that still belongs to
                    // this folder is removed with it, as in `delete(itemId:visited:)`.
                    // See CODE_AUDIT_23 §5.8.
                    let children = model.entries.filter {
                        itemControllable.itemSync(for: $0.childId)?.parentId == model.id
                    }.map {
                        ItemRowModel(itemId: $0.childId, typeId: itemModel.typeId)
                    }
                    allRemovingItems.append(contentsOf: children)
                    // Recursively collect children from nested folders
                    collectChildren(from: children)
                }
            }
        }

        collectChildren(from: items)

        // A folder and its child selected together listed the child twice.
        // See CODE_AUDIT_Folder §5.30.
        var seenIds: Set<UUID> = []
        return allRemovingItems.filter { seenIds.insert($0.itemId).inserted }
    }

    /// Trashes the `candidates` of a delete the user confirmed, except `kept`. All candidates
    /// are trashed and the kept ones restored together, in one step, so a kept child of a
    /// removed folder leaves that folder by the rules of `restore(itemIds:)`.
    /// See CODE_AUDIT_Folder §5.1, §5.4, CODE_AUDIT_21 §5.29.
    @MainActor func confirmRemoval(of candidates: [ItemRowModel], keeping kept: [ItemRowModel]) {
        candidates.forEach {
            markForDeletion(itemId: $0.itemId)
        }
        restore(itemIds: kept.map(\.itemId))
    }
}

// MARK: - Delete / Duplicate / Restore

public extension EditControllable {
    @MainActor func delete(itemId: UUID) async {
        await delete(itemId: itemId, visited: [])
    }

    /// - Parameter visited: Ids already visited on this recursive delete walk. Write-time
    ///   cycle prevention (`addItem(itemId:parentId:)`) means a cycle should never form, but
    ///   an import or CloudKit merge conflict could still produce one — without this guard a
    ///   cyclic folder would recurse forever, deleting items on the way, until the process is
    ///   killed. See CODE_AUDIT_17 §5.14.
    @MainActor private func delete(itemId: UUID, visited: Set<UUID>) async {
        guard !visited.contains(itemId), visited.count < FolderTreeDepthLimit.max else { return }
        var visited = visited
        visited.insert(itemId)

        recordOperation("EditControllable.delete(itemId:)")

        guard let item = await itemControllable.item(for: itemId) as? Model else { return }
        let isTrashed = item.isHidden
        await willDeleteChildren(of: item)
        for entry in item.entries {
            if item.category == .folder {
                // Only a child that still belongs to this folder is part of it: a child the
                // delete panel kept was moved out, and an entry left behind by a move can point
                // at an item that lives elsewhere now. Purging a trashed folder deletes only
                // children that are trashed themselves. See CODE_AUDIT_Folder §5.1.
                guard let child = itemControllable.itemSync(for: entry.childId),
                      child.parentId == item.id,
                      !isTrashed || child.isHidden else { continue }
                await Task.yield()
                await delete(itemId: entry.childId, visited: visited)
            } else if !item.specialCategory {
                linkRegisterController.resetUsedLink(for: ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemControllable.config.module))
                reset(displayState: DisplayStateMask.fullVisible.rawValue, itemId: entry.childId)
            }
        }

        // A trashed item already gave its tags back in `markForDeletion`.
        // See CODE_AUDIT_Folder §5.19.
        if !isTrashed {
            tagController.remove(tags: item.tags, module: itemControllable.config.module)
        }
        linkRegisterController.repairLinks(for: [ItemRowModel(itemId: itemId, typeId: itemControllable.config.module)])
        linkRegisterController.resetUsedLink(for: ItemRowModel(itemId: itemId, typeId: itemControllable.config.module))
        
        IntentDonations.forget(itemId: itemId, module: itemControllable.config.module)
        await itemControllable.delete(itemId: itemId)
    }
    
    /// Duplicates `itemIds` in order, unless a duplicate started from any menu of this module is
    /// still running: a second press is ignored instead of starting an overlapping copy of the
    /// same files. See CODE_AUDIT_Folder §3.18.
    @MainActor func duplicateIgnoringRepeats(itemIds: [UUID]) {
        guard editorModel.duplicateTask == nil, !itemIds.isEmpty else { return }
        let editorModel = editorModel
        editorModel.duplicateTask = Task { @MainActor in
            defer { editorModel.duplicateTask = nil }
            for itemId in itemIds {
                guard let item = itemControllable.itemSync(for: itemId) else { continue }
                await duplicate(item: item)
            }
        }
    }

    @MainActor func duplicate(item: any ItemDataAccessible) async {
        recordOperation("EditControllable.duplicate(item:)")

        guard let model = folderEditModel(for: item.id, scope: .library) else { return }
        let duplicate = await duplicateItem(model, parentId: nil)
        if model.isFolder {
            await duplicateFolderMembers(of: model.id, into: duplicate.id) { child, parentId in
                await duplicateItem(child, parentId: parentId).id
            }
        }
        placeDuplicate(duplicate.id, of: model)
    }

    /// Puts a duplicate where its original is: in the original's folder, and in every collection
    /// that lists the original. A collection only references its members, so this does not
    /// change the copy's visibility. `original` is the permanent-library item.
    /// Shared by every module's duplicate. See CODE_AUDIT_Folder §5.16, §9.9.
    @MainActor func placeDuplicate(_ copyId: UUID, of original: any ItemDataAccessible) {
        if let parentId = original.parentId {
            addItem(itemId: copyId, parentId: parentId)
        }
        guard !original.specialCategory else { return }
        for containerId in itemControllable.itemDataModel.items {
            guard let container = itemControllable.itemSync(for: containerId, noGame: true),
                  container.category.isCollection,
                  container.entries.contains(where: { $0.childId == original.id }) else { continue }
            addItem(itemId: copyId, parentId: containerId)
        }
    }

    /// Duplicates the members of folder `originalFolderId` into its copy `copyFolderId`,
    /// recursing into members that are folders themselves, and stores the copy's new member
    /// list. `duplicateMember` copies one member under the given parent and returns the copy's
    /// id. Only members whose own parent is the folder are copied: a stale entry can point at
    /// an item that lives elsewhere.
    ///
    /// Shared by every module's duplicate, with one recursion guard: `visited` stops a cycle in
    /// the folder graph, `FolderTreeDepthLimit.max` bounds deep nesting.
    /// See CODE_AUDIT_EditItem §5.1-§5.4, CODE_AUDIT_Folder §5.1, §9.9.
    @MainActor func duplicateFolderMembers(
        of originalFolderId: UUID,
        into copyFolderId: UUID,
        visited: Set<UUID> = [],
        duplicateMember: (_ member: Model, _ parentId: UUID) async -> UUID
    ) async {
        guard !visited.contains(originalFolderId), visited.count < FolderTreeDepthLimit.max,
              let originalFolder = folderEditModel(for: originalFolderId, scope: .library) else { return }
        let visited = visited.union([originalFolderId])
        var newEntries: [Model.Entry] = []
        for entry in originalFolder.entries {
            guard !visited.contains(entry.childId),
                  let member = folderEditModel(for: entry.childId, scope: .library),
                  member.parentId == originalFolderId else { continue }
            let memberCopyId = await duplicateMember(member, copyFolderId)
            if member.isFolder {
                await duplicateFolderMembers(of: member.id, into: memberCopyId, visited: visited, duplicateMember: duplicateMember)
            }
            newEntries.append(Model.Entry.newChild(id: memberCopyId))
        }
        guard let copyFolder = folderEditModel(for: copyFolderId, scope: .library) else { return }
        copyFolder.entries = newEntries
        saveFolderEdit(copyFolder, message: String(localized: "Duplicate folder", bundle: .module), scope: .library)
    }

    /// Duplicates `model` and its attached file (if any), without its folder members.
    ///
    /// The copy gets its parent before it is stored. Setting it on the stored instance
    /// afterwards compared the instance with itself inside `replace` and never persisted it.
    /// The copy is persisted also during a running game. See CODE_AUDIT_Folder §5.5, §5.21.
    @MainActor private func duplicateItem(_ model: Model, parentId: UUID?) async -> Model {
        var duplicate = model.duplicate()
        duplicate.parentId = parentId
        if model.category.isCollection {
            // A collection's copy references the same members; `Entry.duplicate()` mints new
            // ids, which for modules whose entry id is the member id pointed at nothing.
            duplicate.entries = model.entries.map { Model.Entry.newChild(id: $0.childId) }
        }
        itemControllable.replace(model: duplicate, isInsert: true, forceSave: true)

        if let fileUrl = model.fileUrl {
            // File-to-file, and a failure is reported instead of silently leaving the copy
            // without a file. See CODE_AUDIT_19 §7.1.
            do {
                try await resetFile(copying: fileUrl, itemId: duplicate.id)
            } catch {
                Logger.editController.error("duplicate(model:) failed to copy the file: \(error.localizedDescription, privacy: .private)")
                itemControllable.itemDataModel.lastPersistenceError = error
                PersistenceIssueCenter.shared.recordFileError(error)
            }
        }
        return duplicate
    }

    /// - Parameter forceSave: `true` trashes the library item also during a game (the Delete
    ///   intents). See CODE_AUDIT_Since_3.0.1 §5.2.
    @MainActor func markForDeletion(itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId),
              !item.isHidden else { return }
        // Idempotent: a second pass over an already trashed item removed the tags twice.
        // See CODE_AUDIT_Folder §5.19.
        tagController.remove(tags: item.tags, module: itemControllable.config.module)
        item.displayState = DisplayStateMask.totalHidden.rawValue
        save(updated: item, message: String(localized: "Delete", bundle: .module), forceSave: forceSave)
        IntentDonations.forget(itemId: itemId, module: itemControllable.config.module)
    }

    @MainActor func restore(itemId: UUID) {
        restore(itemIds: [itemId])
    }

    /// Restores `itemIds` together. A child restored with its folder keeps its place in the
    /// folder; restored one by one, the folder detached its still-trashed children first and
    /// each child then landed at root. A child restored without its folder is taken out of the
    /// folder's entries as well, so purging the folder later cannot delete it.
    /// See CODE_AUDIT_Folder §5.1, §5.4.
    @MainActor func restore(itemIds: [UUID]) {
        let restoring = Set(itemIds)
        for itemId in itemIds {
            restore(itemId: itemId, restoring: restoring)
        }
    }

    @MainActor private func restore(itemId: UUID, restoring: Set<UUID>) {
        trackOperation("EditControllable.restore(itemId:)")

        // Only trashed items are restored: Cancel in an entry-removal panel passes items that
        // were never trashed, and "restoring" them unhid group-hidden items.
        guard var item = editModel(for: itemId),
              item.isHidden else { return }
        let trashed = DisplayStateMask.totalHidden.rawValue

        if item.category == .folder {
            // Children still in the trash that are not restored with the folder are detached
            // from it, in both directions; entries for items that live elsewhere are dropped.
            var keptEntries = item.entries
            for entry in item.entries {
                guard var child = editModel(for: entry.childId) else {
                    keptEntries.removeAll { $0.childId == entry.childId }
                    continue
                }
                if child.displayState == trashed && !restoring.contains(child.id) {
                    keptEntries.removeAll { $0.childId == child.id }
                    if child.parentId == item.id {
                        child.parentId = nil
                        save(updated: child, message: String(localized: "Restore parent", bundle: .module))
                    }
                } else if child.parentId != item.id {
                    keptEntries.removeAll { $0.childId == child.id }
                }
            }
            item.entries = keptEntries
        } else {
            willRestore(item: &item)
        }

        // A parent that stays in the trash (or is gone): the item moves to root, and leaves the
        // parent's entries so the parent's purge cannot reach it.
        if let parentId = item.parentId, !restoring.contains(parentId) {
            let parentItem = editModel(for: parentId)
            if parentItem == nil || parentItem?.displayState == trashed {
                item.parentId = nil
                if let parentItem, parentItem.entries.contains(where: { $0.childId == item.id }) {
                    parentItem.entries.removeAll { $0.childId == item.id }
                    save(updated: parentItem, message: String(localized: "Restore item", bundle: .module))
                }
            }
        }

        tagController.add(tags: item.tags, module: itemControllable.config.module)
        item.displayState = DisplayStateMask.fullVisible.rawValue
        save(updated: item, message: String(localized: "Restore item", bundle: .module))
    }

    @MainActor func removeItem(offsets: IndexSet, itemId: UUID) {
        guard let item = folderEditModel(for: itemId, scope: .library) else { return }
        let rowIds = item.memberRowIds()
        removeMembers(rowIds: Set(offsets.compactMap { rowIds.indices.contains($0) ? rowIds[$0] : nil }), from: itemId)
    }

    /// Removes the members shown by the list rows `rowIds` from the folder or collection
    /// `itemId`. Rows are resolved to entries by id: the visible list can be filtered, skip
    /// trashed members or show nested rows, so its positions are not positions in `entries`.
    /// A folder's removed children move to root. See CODE_AUDIT_Folder §5.15.
    @MainActor func removeMembers(rowIds: Set<UUID>, from itemId: UUID) {
        guard let item = folderEditModel(for: itemId, scope: .library), !rowIds.isEmpty else { return }
        let memberRowIds = item.memberRowIds()
        let removedOffsets = IndexSet(memberRowIds.indices.filter { rowIds.contains(memberRowIds[$0]) })
        guard !removedOffsets.isEmpty else { return }
        let removedEntries = removedOffsets.map { item.entries[$0] }
        var entries = item.entries
        entries.remove(atOffsets: removedOffsets)
        item.entries = entries

        if item.category == .folder {
            // For folders, move children to root level (set parentId = nil) instead of deleting them
            for entry in removedEntries {
                if var childItem = folderEditModel(for: entry.childId, scope: .library), childItem.parentId == item.id {
                    childItem.parentId = nil
                    saveFolderEdit(childItem, message: String(localized: "Removed parent", bundle: .module).localizedLowercase.localizedString, scope: .library)
                    movedFileTree(itemId: childItem.id)
                }
            }
        }
        // For non-folder containers (collections), just remove from entries (no need to modify children)
        saveFolderEdit(item, message: String(localized: "Delete item", bundle: .module), scope: .library)
    }
}
