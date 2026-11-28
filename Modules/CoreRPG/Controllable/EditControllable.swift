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
    @MainActor func willRepairOrphan(itemId: UUID, forceSave: Bool)

    /// The ids of the group items `item`'s entries stand for. Empty for a module without groups.
    @MainActor func groupItemIds(of item: any ItemDataAccessible) -> Set<UUID>

    /// Deletes group items (key) that were owned by an item (value) whose newer version no longer
    /// references them, together with the groups nested in them. A group that another item owns
    /// now is kept. Does nothing for a module without groups.
    @MainActor func removeStaleGroups(_ groupOwners: [UUID: UUID]) async

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
    @MainActor func groupItemIds(of item: any ItemDataAccessible) -> Set<UUID> { [] }
    @MainActor func removeStaleGroups(_ groupOwners: [UUID: UUID]) async {}
    @MainActor func willRestore(item: inout Model) {}
    @MainActor func addItem(sheet: SheetModel, forceSave: Bool) async -> UUID? { nil }
}

// MARK: - Editor Basic Properties

public extension EditControllable {
    /// The header editor's save: one edit, one save and one undo step. `nil` leaves that field
    /// unchanged. See CODE_AUDIT_29 §5.5, §9.4.
    @MainActor func update(id: UUID, name: String?, description: String?, category: ItemListCategory?, tags: [String]?, forceSave: Bool) {
        reset(name: name, description: description, category: category, tags: tags, itemId: id, forceSave: forceSave)
    }

    /// Changes name, description, category and tags as one edit: one save and one undo step, so
    /// no sync can pick up a half-applied item. `nil` leaves that property unchanged.
    ///
    /// A forced edit during a game compares with the library too: the game copy can already
    /// hold the value (entered in the game view) while the library does not. See CODE_AUDIT_Edit_Save §5.14.
    @MainActor func reset(name: String?, description: String?, category: ItemListCategory? = nil, tags: [String]?, itemId: UUID, forceSave: Bool) {
        reset(name: name, description: description, category: category, tags: tags, itemId: itemId, forceSave: forceSave, message: String(localized: "Typing", bundle: .module))
    }

    @MainActor private func reset(name: String?, description: String?, category: ItemListCategory?, tags: [String]?, itemId: UUID, forceSave: Bool, message: String) {
        guard var item = editModel(for: itemId) else { return }
        let library = forcedLibraryValue(for: itemId, forceSave: forceSave)
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sortedTags = tags?.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        var changed = false
        if let category, item.category != category || library.map({ $0.category != category }) == true {
            item.category = category
            changed = true
        }
        if let name, let trimmedName, item.name != name || library.map({ $0.name != trimmedName }) == true {
            item.name = trimmedName
            editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
            changed = true
        }
        if let description, let trimmedDescription, item.description != description || library.map({ $0.description != trimmedDescription }) == true {
            item.description = trimmedDescription
            editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
            changed = true
        }
        if let sortedTags {
            // The persisted counts follow the value the library had.
            let countedTags = library?.tags ?? item.tags
            if item.tags != sortedTags || countedTags != sortedTags {
                // Memory-only game edits leave the persisted tag counts alone. See CODE_AUDIT_29 §5.3.
                if persistsEdit(forceSave: forceSave) {
                    updateTags(addedTags: Array(Set(sortedTags).subtracting(countedTags)), removedTags: Array(Set(countedTags).subtracting(sortedTags)))
                }
                item.tags = sortedTags
                changed = true
            }
        }
        guard changed else { return }
        let base = library == nil ? nil : forcedBase(for: itemId) { base, library in
            if category != nil { base.category = library.category }
            if name != nil { base.name = library.name }
            if description != nil { base.description = library.description }
            if tags != nil { base.tags = library.tags }
        }
        save(updated: item, message: message, forceSave: forceSave, forcedBase: base)
        if name != nil {
            movedFolderChildren(of: item, forceSave: forceSave)
        }
    }

    /// The library value a forced edit compares with, when the item has a game copy during a
    /// game; `nil` otherwise (the item readers see is the one written).
    @MainActor private func forcedLibraryValue(for itemId: UUID, forceSave: Bool) -> Model? {
        guard forceSave, gameCopy(of: itemId) != nil else { return nil }
        return itemControllable.itemSync(for: itemId, noGame: true) as? Model
    }

    /// Saves a single-field edit (`edit` sets the field on the item and returns whether it
    /// changed it). With a game copy, a forced edit is also written when only the library lacks
    /// the value. See CODE_AUDIT_Edit_Save §5.14.
    /// The shared single-field setter of every module (CODE_AUDIT_Edit_Save §9.5), with the write
    /// policy as a required parameter.
    @discardableResult
    @MainActor func saveField<Value: Equatable>(
        itemId: UUID,
        _ keyPath: WritableKeyPath<Model, Value>,
        to value: Value,
        message: String,
        forceSave: Bool
    ) -> Model? {
        guard var item = editModel(for: itemId) else { return nil }
        let library = forcedLibraryValue(for: itemId, forceSave: forceSave)
        guard item[keyPath: keyPath] != value || library.map({ $0[keyPath: keyPath] != value }) == true else { return nil }
        item[keyPath: keyPath] = value
        let base = library == nil ? nil : forcedBase(for: itemId) { base, library in
            base[keyPath: keyPath] = library[keyPath: keyPath]
        }
        save(updated: item, message: message, forceSave: forceSave, forcedBase: base)
        return item
    }

    /// A folder's name is part of its descendants' file paths. Renaming it left their files under
    /// the old name. Only when the rename is persisted. See CODE_AUDIT_Folder §5.30.
    @MainActor private func movedFolderChildren(of item: Model, forceSave: Bool) {
        guard item.isFolder, persistsEdit(forceSave: forceSave) else { return }
        for childId in item.entries.map(\.childId) where itemControllable.itemSync(for: childId, noGame: true)?.parentId == item.id {
            movedFileTree(itemId: childId)
        }
    }

    @MainActor func reset(category: ItemListCategory, itemId: UUID, forceSave: Bool) {
        _ = saveField(itemId: itemId, \.category, to: category, message: String(localized: "Change to \(category.title)", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(description: String, itemId: UUID, forceSave: Bool) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = saveField(itemId: itemId, \.description, to: trimmed, message: String(localized: "Typing", bundle: .module), forceSave: forceSave) else { return }
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
    }

    @MainActor func reset(displayState: Int, itemId: UUID, forceSave: Bool) {
        _ = saveField(itemId: itemId, \.displayState, to: displayState, message: String(localized: "Change Display", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(name: String, itemId: UUID, forceSave: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = saveField(itemId: itemId, \.name, to: trimmed, message: String(localized: "Typing", bundle: .module), forceSave: forceSave) else { return }
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
        movedFolderChildren(of: item, forceSave: forceSave)
    }

    @MainActor func reset(tags: [String], itemId: UUID, forceSave: Bool) {
        reset(name: nil, description: nil, category: nil, tags: tags, itemId: itemId, forceSave: forceSave, message: String(localized: "Changed tags", bundle: .module))
    }

    @MainActor func reset(hidden: Bool, itemId: UUID, forceSave: Bool) {
        _ = saveField(itemId: itemId, \.isGroupHiddenToggle, to: hidden, message: String(localized: "Change to \(hidden ? "hide" : "show")", bundle: .module), forceSave: forceSave)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID, forceSave: Bool) {
        _ = saveField(itemId: itemId, \.fileUrl, to: fileUrl, message: String(localized: "Change file", bundle: .module), forceSave: forceSave)
    }

    /// Also used by `updateTagCounts` (EditControllable+Persistence.swift).
    @MainActor internal func updateTags(addedTags: [String], removedTags: [String]) {
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

    @MainActor func willRepairOrphan(itemId: UUID, forceSave: Bool) {
        guard var item = editModel(for: itemId) else { return }
        guard item.groupId != nil else { return }
        item.groupId = nil
        save(updated: item, message: String(localized: "Repair orphan", bundle: .module), forceSave: forceSave)
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

    @MainActor func willRepairOrphan(itemId: UUID, forceSave: Bool) {}

    /// Removes `itemId` from every folder other than its own parent. After an import moved the
    /// item (to another folder or to root), its old folder still listed it. The loop used to
    /// stop at the first folder that did not contain the item, and skipped items moved to
    /// root entirely. See CODE_AUDIT_Folder §5.6.
    @MainActor func repairFolder(itemId: UUID, forceSave: Bool) {
        repairFolders(itemIds: [itemId], forceSave: forceSave)
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
    ///
    /// - Parameter forceSave: The import's own write policy: a persisted import repairs the
    ///   library too, not only game memory. See CODE_AUDIT_Edit_Save §5.20.
    @MainActor func repairFolders(itemIds: Set<UUID>, forceSave: Bool) {
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
            save(updated: folderItem, message: String(localized: "removed item from folder", bundle: .module), forceSave: forceSave)
        }
    }
    
}

// MARK: - Group Items / Carousel Items

public extension EditControllable {
    /// Takes `childId` out of the group item `itemId` and shows it again. Only the group-hidden
    /// bit is cleared: assigning the whole mask made a trashed child fully visible.
    /// See CODE_AUDIT_Edit_Save §5.26.
    @MainActor func removeGroup(itemId: UUID, childId: UUID, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId else { return }
        asOneUndoStep(String(localized: "Remove groupped item", bundle: .module)) {
            var entries = item.entries
            entries.removeAll(where: { $0.childId == childId })
            item.entries = entries

            reset(hidden: false, itemId: childId, forceSave: forceSave)
            save(updated: item, message: String(localized: "Remove groupped item", bundle: .module), forceSave: forceSave)
        }
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
            // `.entry` is the plain item category of the current data model. `.item` is a legacy
            // category that Validate would convert and tag "Item".
            itemCategory = .entry
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
    @MainActor func removeEntry(source: ItemRowModel, forceSave: Bool) -> Bool {
        guard source.typeId == itemControllable.config.module, let entryId = source.entryId, let updatedModel = editModel(for: source.itemId) else { return false }

        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Delete Entry", bundle: .module), forceSave: forceSave)
        return true
    }
}
