// @copyright André Trettin

import SwiftUI
import os.log

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessible & ItemDiffComparable & ItemLinkRegistrable & ModelType

    var itemControllable: any ItemControllable { get }
    var fileUrlDataController: FileUrlDataController? { get }
    @MainActor var linkRegisterController: LinkRegisterController { get }
    var tagController: TagController { get }
    
    @MainActor var editorModel: ItemEditorModel { get }

    // overwrite extensions
    @MainActor func duplicate(item: any ItemDataAccessible) async
    @MainActor func validateBeforeSave(model: Model)
    @MainActor func willDeleteChildren(of item: Model) async
    @MainActor func willRestore(item: inout Model)
    @MainActor func isOrphanedHidden(itemId: UUID) -> Bool
    @MainActor func willRepairOrphan(itemId: UUID)

    /// Creates a new real, persisted item from a sheet built elsewhere
    /// (e.g. a generated table outcome) — the sheet's `name`/`description`
    /// become the new item's, and its `entries` become the new item's own
    /// entries. Returns the new item's id, or `nil` if nothing was created.
    /// `forceSave` bypasses the in-game-memory-only save path (see
    /// `ItemControllable.replace(model:isInsert:forceSave:)`) — pass `true`
    /// when adding on behalf of a network push during an active game, where
    /// there's no later UI save to eventually flush the change.
    /// Default is a no-op: only modules that can meaningfully turn an
    /// arbitrary sheet into one of their own items (currently CharacterRPG's
    /// values) need to implement this.
    @MainActor func addItem(sheet: SheetModel, forceSave: Bool) async -> UUID?
}

// MARK: - Diagnostics

public extension EditControllable {
    /// Counts one file or save operation for the diagnostic log. Synchronous, so no caller
    /// needs a `Task` for it. See CODE_AUDIT_EditItem §3.4, CODE_AUDIT_26 §9.10.
    @MainActor func recordOperation(_ function: String) {
        CloudKitOperationCounter.shared.recordOperation(function: function)
    }

    @MainActor func trackOperation(_ function: String) {
        recordOperation(function)
    }
}

public extension EditControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    // Delegates to `itemControllable`'s own safe default rather than
    // force-unwrapping a second time here. See CODE_AUDIT §5.5.
    @MainActor var linkRegisterController: LinkRegisterController { itemControllable.linkRegisterController }

    @MainActor var cacheItemListModel: CacheItemListModel {
        editorModel.cacheItemListModel
    }

    @MainActor func validateBeforeSave(model: Model) {}
    @MainActor func willDeleteChildren(of item: Model) async {}
    @MainActor func willRestore(item: inout Model) {}
    @MainActor func addItem(sheet: SheetModel, forceSave: Bool) async -> UUID? { nil }

    /// Convenience overload preserving every pre-existing 1-argument call
    /// site (memory-only during an active game, matching historical
    /// behavior).
    @MainActor func addItem(sheet: SheetModel) async -> UUID? {
        await addItem(sheet: sheet, forceSave: false)
    }
}

// MARK: - Editor Basic Properties

public extension EditControllable {
    @MainActor func update(id: UUID, name: String, description: String, category: ItemListCategory, tags: [String], forceSave: Bool = false) {
        reset(name: name, itemId: id, forceSave: forceSave)
        reset(description: description, itemId: id, forceSave: forceSave)
        reset(category: category, itemId: id, forceSave: forceSave)
        reset(tags: tags, itemId: id, forceSave: forceSave)
    }

    /// Changes name, description and tags as one edit: one save and one undo step, so no sync can
    /// pick up a half-applied item. `nil` leaves that property unchanged.
    @MainActor func reset(name: String?, description: String?, tags: [String]?, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        var changed = false
        if let name, item.name != name {
            item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
            changed = true
        }
        if let description, item.description != description {
            item.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
            changed = true
        }
        if let tags {
            let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
            if item.tags != sortedTags {
                let addedTags = Array(Set(sortedTags).subtracting(item.tags))
                let removedTags = Array(Set(item.tags).subtracting(sortedTags))
                updateTags(addedTags: addedTags, removedTags: removedTags)
                item.tags = sortedTags
                changed = true
            }
        }
        guard changed else { return }
        save(updated: item, message: String(localized: "Typing", bundle: .module), forceSave: forceSave)
        // A folder's name is part of its descendants' file paths (see `reset(name:itemId:)`).
        if name != nil, item.isFolder, forceSave || !itemControllable.itemDataModel.isGameMode {
            for childId in item.entries.map(\.childId) where itemControllable.itemSync(for: childId, noGame: true)?.parentId == item.id {
                movedFileTree(itemId: childId)
            }
        }
    }

    @MainActor func reset(category: ItemListCategory, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.category != category else { return }
        item.category = category
        save(updated: item, message: String(localized: "Change to \(category.title)", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(description: String, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.description != description else { return }
        item.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module), forceSave: forceSave)
    }
    
    @MainActor func reset(displayState: Int, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.displayState != displayState else { return }
        item.displayState = displayState
        save(updated: item, message: String(localized: "Change Display", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(name: String, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.name != name else { return }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module), forceSave: forceSave)
        // A folder's name is part of its descendants' file paths. Renaming it left their files
        // under the old name. Only when the rename is persisted. See CODE_AUDIT_Folder §5.30.
        if item.isFolder, forceSave || !itemControllable.itemDataModel.isGameMode {
            for childId in item.entries.map(\.childId) where itemControllable.itemSync(for: childId, noGame: true)?.parentId == item.id {
                movedFileTree(itemId: childId)
            }
        }
    }

    @MainActor func reset(tags: [String], itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard item.tags != sortedTags else { return }
        let addedTags = Array(Set(sortedTags).subtracting(item.tags))
        let removedTags = Array(Set(item.tags).subtracting(sortedTags))
        updateTags(addedTags: addedTags, removedTags: removedTags)
        item.tags = sortedTags
        save(updated: item, message: String(localized: "Changed tags", bundle: .module), forceSave: forceSave)
    }
    
    @MainActor func reset(hidden: Bool, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.isGroupHiddenToggle != hidden else { return }
        item.isGroupHiddenToggle = hidden
        save(updated: item, message: String(localized: "Change to \(hidden ? "hide" : "show")", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.fileUrl != fileUrl else { return }
        item.fileUrl = fileUrl
        save(updated: item, message: String(localized: "Change file", bundle: .module), forceSave: forceSave)
    }

    @MainActor private func updateTags(addedTags: [String], removedTags: [String]) {
        tagController.add(tags: addedTags, module: itemControllable.config.module)
        // Removed tags lose their count too; otherwise they stayed in suggestions forever.
        // See CODE_AUDIT_Folder §5.19.
        tagController.remove(tags: removedTags, module: itemControllable.config.module)
    }
}

// MARK: - Groupable Models

/// A domain model that supports being organized into a same-type "group" — a
/// phase-1-hidden sub-item owned by a parent item via `groupId`, distinct from the
/// plain folder/collection `parentId` hierarchy. CharacterRPG's `ValueModel` and
/// AdventureRPG's `AdventureModel` are the only two conformers today; both
/// independently reimplemented the exact same orphan-handling trio below before this
/// was hoisted into a shared, constrained default. See CODE_AUDIT_EditItem §9.5.
public protocol GroupableModel: ItemDataAccessible {
    var groupId: UUID? { get set }
}

public extension EditControllable where Model: GroupableModel {
    @MainActor func isOrphanedHidden(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return false }
        guard item.displayState == DisplayStateMask.groupHidden.rawValue && item.parentId == nil else { return false }
        if let groupId = item.groupId {
            // Hidden with a groupId: orphaned if the parent is gone or deleted.
            let parent = itemControllable.itemSync(for: groupId)
            return parent == nil || parent?.isHidden == true
        }
        return true // no parentId, no groupId → phase-1 orphan
    }

    @MainActor func willRepairOrphan(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.groupId != nil else { return }
        item.groupId = nil
        save(updated: item, message: String(localized: "Repair orphan", bundle: .module))
    }

    @MainActor func willRestore(item: inout Model) {
        guard let groupId = item.groupId else { return }
        // Clear groupId if the parent is deleted or no longer exists.
        if let groupItem = editModel(for: groupId) {
            if groupItem.isHidden {
                item.groupId = nil
            }
        } else {
            item.groupId = nil
        }
    }
}

// MARK: - Other

public extension EditControllable {
    @MainActor func isOrphanedHidden(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) else { return false }
        return item.parentId == nil && item.displayState == DisplayStateMask.groupHidden.rawValue
    }

    @MainActor func willRepairOrphan(itemId: UUID) {}

    /// Removes `itemId` from every folder other than its own parent. After an import moved the
    /// item (to another folder or to root), its old folder still listed it. The loop used to
    /// stop at the first folder that did not contain the item, and skipped items moved to
    /// root entirely. See CODE_AUDIT_Folder §5.6.
    @MainActor func repairFolder(itemId: UUID) {
        repairFolders(itemIds: [itemId])
    }

    /// `repairFolder(itemId:)` for a whole import batch in one pass over the library: run per
    /// item, an import of n items walked every item n times. See CODE_AUDIT_Folder §7.3.
    ///
    /// The child decides membership (CODE_AUDIT_Folder §9.8): a folder lists exactly the known
    /// items whose `parentId` is that folder.
    /// - An item of the batch leaves every other folder and is added to its own folder if that
    ///   folder does not list it, for example when the folder came earlier in the import.
    /// - A folder of the batch, whose members the merge unioned, drops members that now live
    ///   elsewhere (a removal made on another device does not come back) and lists the local
    ///   children it is missing. Members not known on this device stay; they may still arrive.
    @MainActor func repairFolders(itemIds: Set<UUID>) {
        var parentIds: [UUID: UUID] = [:]
        var rootItemIds: Set<UUID> = []
        var batchFolderIds: Set<UUID> = []
        var batchChildrenByParent: [UUID: [UUID]] = [:]
        for itemId in itemIds {
            guard let item = itemControllable.itemSync(for: itemId) else { continue }
            if item.isFolder {
                batchFolderIds.insert(itemId)
            }
            if let parentId = item.parentId {
                parentIds[itemId] = parentId
                batchChildrenByParent[parentId, default: []].append(itemId)
            } else {
                rootItemIds.insert(itemId)
            }
        }
        guard !parentIds.isEmpty || !rootItemIds.isEmpty else { return }

        // Children of the batch's folders by their own parent, in one pass over the library.
        var childrenByFolder: [UUID: [UUID]] = [:]
        if !batchFolderIds.isEmpty {
            for id in itemControllable.itemDataModel.items {
                guard let parentId = itemControllable.itemSync(for: id)?.parentId,
                      batchFolderIds.contains(parentId) else { continue }
                childrenByFolder[parentId, default: []].append(id)
            }
        }

        for id in itemControllable.itemDataModel.items {
            guard let checkItem = itemControllable.itemSync(for: id), checkItem.isFolder else { continue }
            let isBatchFolder = batchFolderIds.contains(id)
            func isStale(_ childId: UUID) -> Bool {
                if rootItemIds.contains(childId) { return true }
                if let parentId = parentIds[childId] { return parentId != id }
                guard isBatchFolder, let child = itemControllable.itemSync(for: childId) else { return false }
                return child.parentId != id
            }
            let listed = Set(checkItem.entries.map(\.childId))
            var missing: [UUID] = []
            var missingIds = Set<UUID>()
            for childId in (batchChildrenByParent[id] ?? []) + (isBatchFolder ? childrenByFolder[id] ?? [] : [])
            where !listed.contains(childId) && missingIds.insert(childId).inserted {
                missing.append(childId)
            }
            let hasDuplicates = FolderEntryMerge.deduplicated(checkItem.entries, id: \.id, childId: \.childId) != nil
            guard checkItem.entries.contains(where: { isStale($0.childId) }) || !missing.isEmpty || hasDuplicates,
                  let folderItem = editModel(for: id) else { continue }
            folderItem.entries.removeAll { isStale($0.childId) }
            folderItem.entries.append(contentsOf: missing.map { Model.Entry.newChild(id: $0) })
            if let unique = FolderEntryMerge.deduplicated(folderItem.entries, id: \.id, childId: \.childId) {
                folderItem.entries = unique
            }
            save(updated: folderItem, message: String(localized: "removed item from folder", bundle: .module))
        }
    }
    
}

// MARK: - Group Items / Carousel Items

public extension EditControllable {
    /// Groups `childId` under the item `itemId`: the child is hidden and shown only as part of
    /// that item. Folders and collections are not groups — a collection only references its
    /// members and a folder only places them — so for those parents this adds the member like
    /// "Add into" does, without hiding it. See CODE_AUDIT_Folder §5.16.
    @MainActor func addGroup(itemId: UUID, childId: UUID, forceSave: Bool = false) {
        guard let item = editModel(for: itemId) else { return }
        if item.specialCategory {
            guard item.id != childId, item.hasEntry(entryId: childId) == false else { return }
            addItem(itemId: childId, parentId: itemId)
            return
        }
        guard item.id != childId && item.hasEntry(entryId: childId) == false else { return }
        let childItem = itemControllable.itemOrEmpty(for: childId)
        guard childItem.category != .folder && childItem.category != itemControllable.collectionCategory  else { return }
        var entries = item.entries

        let entry =  Model.Entry.newChild(id: childId)
        entries.append(entry)
        item.entries = entries

        reset(displayState: DisplayStateMask.groupHidden.rawValue, itemId: childId, forceSave: forceSave)
        save(updated: item, message: String(localized: "Add groupped item", bundle: .module), forceSave: forceSave)
    }

    @MainActor func removeGroup(itemId: UUID, childId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId else { return }
        var entries = item.entries
        entries.removeAll(where: { $0.childId == childId })
        item.entries = entries
        
        reset(displayState: DisplayStateMask.fullVisible.rawValue, itemId: childId)
        save(updated: item, message: String(localized: "Remove groupped item", bundle: .module))
    }
}


// MARK: - Menu

public extension EditControllable {
    func addNew(type: EditControllerAddType) async -> (any ItemDataAccessible)? {
        let itemCategory: ItemListCategory
        if type == .folder {
            itemCategory = .folder
        } else if type == .collection {
            itemCategory = itemControllable.collectionCategory
        } else {
            itemCategory = .item
        }
        let itemId = await itemControllable.addNew(type: itemCategory)
        return await itemControllable.item(for: itemId)
    }
    

    @MainActor func moveItems(source: IndexSet, destination: Int, itemId: UUID) {
        guard let item = folderEditModel(for: itemId, scope: .library) else { return }
        var entries = item.entries
        entries.move(fromOffsets: source, toOffset: destination)
        item.entries = entries
        saveFolderEdit(item, message: String(localized: "Move entries", bundle: .module), scope: .library)
    }

    /// Moves the member shown by row `rowId` to the position of the member shown by
    /// `targetRowId` in the folder or collection `itemId`. Resolved by row id, not by list
    /// position. See CODE_AUDIT_Folder §5.15.
    @MainActor func moveMember(rowId: UUID, to targetRowId: UUID, in itemId: UUID) {
        guard let item = folderEditModel(for: itemId, scope: .library) else { return }
        let memberRowIds = item.memberRowIds()
        guard let from = memberRowIds.firstIndex(of: rowId),
              let to = memberRowIds.firstIndex(of: targetRowId),
              from != to else { return }
        moveItems(source: IndexSet(integer: from), destination: to > from ? to + 1 : to, itemId: itemId)
    }
}

// MARK: - New Entry Editor

public extension EditControllable {
    /// Whether the entry was removed; a caller that mirrors the change in a view model does so only
    /// then. See CODE_AUDIT_26 §5.64.
    @discardableResult
    @MainActor func removeEntry(source: ItemRowModel, forceSave: Bool = false) -> Bool {
        guard source.typeId == itemControllable.config.module, let entryId = source.entryId, let updatedModel = editModel(for: source.itemId) else { return false }

        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Delete Entry", bundle: .module), forceSave: forceSave)
        return true
    }
}

// MARK: - Controller Maintenance

public extension EditControllable {
    @MainActor func editModel(for itemId: UUID) -> Model? {
        return itemControllable.itemSync(for: itemId)?.copy() as? Model
    }

    /// Clears any editor state still referencing a deleted item, so a stale/removed model
    /// doesn't linger in the header editor, the group/sheet editor, or the item link cache.
    @MainActor func removeFromEditors(itemId: UUID) {
        if (editorModel.currentModel as? Model)?.id == itemId {
            editorModel.undoManaged.resetValue(nil)
        }
        if editorModel.sheetEditorModel.itemId == itemId {
            editorModel.sheetEditorModel.itemId = nil
            editorModel.sheetEditorModel.entryId = nil
        }
        editorModel.cacheItemListModel.reset(itemId: itemId)
    }

    @MainActor func saveChanges(to newValue: Model, name: String, forceSave: Bool = false) {
        // A fixed identifier: the counter logs it as public, and `name` can carry a user tag
        // ("Add <tag>"). See CODE_AUDIT_Folder §6.5.
        trackOperation("EditControllable.saveChanges(to:name:)")

        if let previous = itemControllable.itemSync(for: newValue.id) as? Model {
            let (added, removed) = newValue.changedLinkRegisterModels(oldValue: previous)

            linkRegisterController.deregister(links: removed)
            linkRegisterController.register(links: added)
        } else {
            let added = newValue.linkRegisterModels
            linkRegisterController.register(links: added)
        }

        editorModel.undoManaged.previousValue(itemControllable.itemOrEmpty(for: newValue.id).copy(), title: name)
        itemControllable.replace(model: newValue, isInsert: false, forceSave: forceSave)
    }

    @MainActor func save(updated: any Observable) {
        guard let updated = updated as? Model else { return }
        save(with: String(localized: "update from sync", bundle: .module), currentModel: updated)
    }

    @MainActor func save(updated: Model, message: String, forceSave: Bool = false) {
        save(with: message, currentModel: updated, forceSave: forceSave)
    }

    @MainActor func setCurrentItem(to item: ItemRowTreeModel) {
        guard editorModel.sheetEditorModel.itemId != item.model.itemId else {
            editorModel.sheetEditorModel.entryId <=> item.model.entryId
            editorModel.sheetEditorModel.module = item.model.typeId
            return
        }
        guard let model = itemControllable.copy(of: item.model.itemId) as? Model else { return }
        setCurrentItem(model: model, entryId: item.model.entryId, module: item.model.typeId)
    }
    
    @MainActor func setCurrentItem(model: Model, entryId: UUID? = nil, module: NetworkModules? = nil) {
        if model.id != editorModel.sheetEditorModel.itemId {
            editorModel.cacheItemListModel.resetItemLink()
            editorModel.undoManaged.resetValue(model)
            editorModel.sheetEditorModel.itemId = model.id
        }
        editorModel.sheetEditorModel.entryId <=> entryId
        editorModel.sheetEditorModel.module = module ?? itemControllable.config.module
    }

    @MainActor func save(with name: String, currentModel: Model, forceSave: Bool = false) {
        validateBeforeSave(model: currentModel)
        guard !itemControllable.isEqual(with: currentModel) else { return }
        saveChanges(to: currentModel, name: name, forceSave: forceSave)
    }
}
