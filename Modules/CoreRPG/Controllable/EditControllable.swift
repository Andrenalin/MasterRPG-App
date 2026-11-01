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
    /// Fires a diagnostic CloudKit-operation-count update. An `async` caller should
    /// `await` this directly; a synchronous caller has no choice but to fire-and-forget
    /// and should go through `trackOperation(_:)` below instead of hand-copying a
    /// `Task { await ... }`. See CODE_AUDIT_EditItem §3.4.
    @MainActor func recordOperation(_ function: String) async {
        await CloudKitOperationCounter.shared.recordOperation(function: function, file: "EditControllable.swift")
    }

    @MainActor func trackOperation(_ function: String) {
        Task { await recordOperation(function) }
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

    @MainActor func reset(category: ItemListCategory, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.category != category else { return }
        item.category = category
        save(updated: item, message: String(localized: "Change to \(category.title)", bundle: .module).localizedString, forceSave: forceSave)
    }

    @MainActor func reset(description: String, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.description != description else { return }
        item.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module).localizedString, forceSave: forceSave)
    }
    
    @MainActor func reset(displayState: Int, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.displayState != displayState else { return }
        item.displayState = displayState
        save(updated: item, message: String(localized: "Change Display", bundle: .module).localizedString, forceSave: forceSave)
    }

    @MainActor func reset(name: String, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.name != name else { return }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module).localizedString, forceSave: forceSave)
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
        save(updated: item, message: String(localized: "Changed tags", bundle: .module).localizedString, forceSave: forceSave)
    }
    
    @MainActor func reset(hidden: Bool, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.isGroupHiddenToggle != hidden else { return }
        item.isGroupHiddenToggle = hidden
        save(updated: item, message: String(localized: "Change to \(hidden ? "hide" : "show")", bundle: .module).localizedString, forceSave: forceSave)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID, forceSave: Bool = false) {
        guard var item = editModel(for: itemId) else { return }
        guard item.fileUrl != fileUrl else { return }
        item.fileUrl = fileUrl
        save(updated: item, message: String(localized: "Change file", bundle: .module).localizedString, forceSave: forceSave)
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
            return parent == nil || parent?.displayState == DisplayStateMask.totalHidden.rawValue
        }
        return true // no parentId, no groupId → phase-1 orphan
    }

    @MainActor func willRepairOrphan(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.groupId != nil else { return }
        item.groupId = nil
        save(updated: item, message: String(localized: "Repair orphan", bundle: .module).localizedString)
    }

    @MainActor func willRestore(item: inout Model) {
        guard let groupId = item.groupId else { return }
        // Clear groupId if the parent is deleted or no longer exists.
        if let groupItem = editModel(for: groupId) {
            if groupItem.displayState == DisplayStateMask.totalHidden.rawValue {
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
            save(updated: folderItem, message: String(localized: "removed item from folder", bundle: .module).localizedString)
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
        save(updated: item, message: String(localized: "Add groupped item", bundle: .module).localizedString, forceSave: forceSave)
    }

    @MainActor func removeGroup(itemId: UUID, childId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId else { return }
        var entries = item.entries
        entries.removeAll(where: { $0.childId == childId })
        item.entries = entries
        
        reset(displayState: DisplayStateMask.fullVisible.rawValue, itemId: childId)
        save(updated: item, message: String(localized: "Remove groupped item", bundle: .module).localizedString)
    }
}

// MARK: - Folder / Collection

/// Where a folder or collection membership edit reads and writes.
public enum FolderEditScope: Sendable {
    /// The permanent library copy, persisted also during a running game. Edits from the library
    /// UI use this: a plain `save` lands in game memory only during a game and is lost at game
    /// end, while the file moves it triggers are real. See CODE_AUDIT_Folder §5.21.
    case library
    /// Whatever `editModel(for:)`/`save(updated:message:)` use now — the import repair, which
    /// runs on game deliveries too.
    case current
}

public extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?) {
        addItem(itemId: itemId, parentId: parentId, scope: .library)
    }

    @MainActor func remove(itemId: UUID, parentId: UUID, oneUp: Bool) {
        guard let parentItem = folderEditModel(for: parentId, scope: .library) else { return }
        if parentItem.isFolder, itemControllable.itemSync(for: itemId, noGame: true)?.parentId == parentId {
            removeItemFromParent(itemId: itemId, oneUp: oneUp, scope: .library)
        } else {
            // A collection, or a folder whose entry for this item is stale (the item lives in
            // another folder or at root): only the entry is removed. Going through the item's own
            // parent here left the stale entry with no way to remove it. See CODE_AUDIT_Folder §5.30.
            parentItem.entries.removeAll(where: { $0.childId == itemId })
            saveFolderEdit(parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString, scope: .library)
        }
    }

    @MainActor func removeItemFromParent(itemId: UUID, oneUp: Bool, moveFiles: Bool = true) {
        removeItemFromParent(itemId: itemId, oneUp: oneUp, moveFiles: moveFiles, scope: .current)
    }

    @MainActor func cleanFolder(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.entries.removeAll {
            guard let child = itemControllable.itemSync(for: $0.childId) else { return true }
            if child.parentId != itemId {
                return true
            }
            return false
        }
        // A member listed by two entries (see `FolderEntryMerge.deduplicated`) is repaired here
        // too, so "Validate & Repair" writes the fix and its final save sends it to other devices.
        if let unique = FolderEntryMerge.deduplicated(item.entries, id: \.id, childId: \.childId) {
            item.entries = unique
        }
        save(updated: item, message: String(localized: "update folder", bundle: .module).localizedString)
    }
}

extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?, scope: FolderEditScope) {
        guard let parentId, itemId != parentId,
              let parentItem = folderEditModel(for: parentId, scope: scope),
              var item = folderEditModel(for: itemId, scope: scope) else { return }
        // Refuse a link that would make `itemId` an ancestor of itself: if `parentId` is
        // already reachable by descending from `itemId` through folder/collection membership,
        // linking `itemId` under `parentId` below would close the loop. Every recursive
        // search/list tree-builder (`buildFolderTreeNode`, `appendToFlat`, …) walks this exact
        // `entries`/`childId` graph assuming it's acyclic and has no cycle guard of its own.
        guard !isDescendant(parentId, of: itemId) else { return }
        if parentItem.isFolder && item.parentId != nil {
            removeItemFromParent(itemId: itemId, oneUp: false, moveFiles: false, scope: scope)
            guard let refreshed = folderEditModel(for: itemId, scope: scope) else { return }
            item = refreshed
        }

        if item.isFolder && (parentItem.specialCategory && !parentItem.isFolder) {
            return
        }

        var entries = parentItem.entries
        if parentItem.category != .item {
            let entry = Model.Entry.newChild(id: itemId)
            if parentItem.category == .folder {
                entries.removeAll { $0.childId == itemId }
            }
            // A collection only references its members and may list one several times.
            entries.append(entry)
            if parentItem.category == .folder {
                entries = entries.sorted {
                    let name1 = itemControllable.nameSync(itemId: $0.childId)
                    let name2 = itemControllable.nameSync(itemId: $1.childId)
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            }
        }

        var shouldCheckForMove: Bool = false
        if parentItem.category == .folder || parentItem.category == .item {
            item.parentId <=> parentItem.id
            if parentItem.category == .item {
                item.displayState <=> 1
            }
            saveFolderEdit(item, message: String(localized: "Added parent", bundle: .module).localizedString, scope: scope)
            shouldCheckForMove = true
        }

        if parentItem.category != .item {
            parentItem.entries <=> entries
        }
        saveFolderEdit(parentItem, message: String(localized: "Added item", bundle: .module).localizedString, scope: scope)

        if shouldCheckForMove {
            movedFileTree(itemId: itemId)
        }
    }

    @MainActor func removeItemFromParent(itemId: UUID, oneUp: Bool, moveFiles: Bool = true, scope: FolderEditScope) {
        guard var item = folderEditModel(for: itemId, scope: scope), let parentId = item.parentId else { return }
        item.parentId = nil
        saveFolderEdit(item, message: String(localized: "Removed parent", bundle: .module).localizedLowercase.localizedString, scope: scope)

        guard let parentItem = folderEditModel(for: parentId, scope: scope) else { return }
        var entries = parentItem.entries
        entries.removeAll(where: { $0.childId == itemId })
        parentItem.entries = entries
        saveFolderEdit(parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString, scope: scope)

        guard oneUp && parentItem.parentId != nil else {
            if moveFiles {
                movedFileTree(itemId: itemId)
            }
            return
        }
        addItem(itemId: itemId, parentId: parentItem.parentId, scope: scope)
    }

    /// Returns true if `candidateId` is reachable from `rootId` by descending through folder/
    /// collection membership (`entries.childId`) — i.e. whether `rootId` is already an
    /// ancestor of `candidateId` in that graph. `visited` makes the walk itself cycle-safe in
    /// case one already exists somehow, rather than relying on the graph being acyclic.
    @MainActor private func isDescendant(_ candidateId: UUID, of rootId: UUID) -> Bool {
        var visited: Set<UUID> = []
        var stack: [UUID] = [rootId]
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            if current == candidateId { return true }
            guard let currentItem = itemControllable.itemSync(for: current) else { continue }
            stack.append(contentsOf: currentItem.entries.map(\.childId))
        }
        return false
    }

    @MainActor public func folderEditModel(for itemId: UUID, scope: FolderEditScope) -> Model? {
        switch scope {
        case .library:
            itemControllable.itemSync(for: itemId, noGame: true)?.copy() as? Model
        case .current:
            editModel(for: itemId)
        }
    }

    @MainActor public func saveFolderEdit(_ item: Model, message: String, scope: FolderEditScope) {
        switch scope {
        case .current:
            save(updated: item, message: message)
        case .library:
            validateBeforeSave(model: item)
            guard !itemControllable.libraryModel(id: item.id, matches: item) else { return }
            if let stored = itemControllable.itemSync(for: item.id, noGame: true) {
                let previous = stored.copy()
                editorModel.markLibraryScopedUndo(previous)
                editorModel.undoManaged.previousValue(previous, title: message)
            }
            itemControllable.persistMembershipChange(model: item)
        }
    }

    /// Moves the files of `itemId` and, for a folder, of everything below it, to match their
    /// folder path. Moving a folder used to leave its descendants' files at the old path.
    /// See CODE_AUDIT_Folder §5.30.
    @MainActor func movedFileTree(itemId: UUID) {
        var visited: Set<UUID> = []
        var stack = [itemId]
        while let current = stack.popLast(), visited.count < FolderTreeDepthLimit.max * FolderTreeDepthLimit.max {
            guard visited.insert(current).inserted,
                  let item = itemControllable.itemSync(for: current, noGame: true) else { continue }
            movedFile(itemId: current)
            if item.isFolder {
                stack.append(contentsOf: item.entries.map(\.childId).filter {
                    itemControllable.itemSync(for: $0, noGame: true)?.parentId == current
                })
            }
        }
    }
}

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

        await recordOperation("EditControllable.delete(itemId:)")

        guard let item = await itemControllable.item(for: itemId) as? Model else { return }
        let isTrashed = item.displayState == DisplayStateMask.totalHidden.rawValue
        await willDeleteChildren(of: item)
        for entry in item.entries {
            if item.category == .folder {
                // Only a child that still belongs to this folder is part of it: a child the
                // delete panel kept was moved out, and an entry left behind by a move can point
                // at an item that lives elsewhere now. Purging a trashed folder deletes only
                // children that are trashed themselves. See CODE_AUDIT_Folder §5.1.
                guard let child = itemControllable.itemSync(for: entry.childId),
                      child.parentId == item.id,
                      !isTrashed || child.displayState == DisplayStateMask.totalHidden.rawValue else { continue }
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
        await recordOperation("EditControllable.duplicate(item:)")

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
        saveFolderEdit(copyFolder, message: String(localized: "Duplicate folder", bundle: .module).localizedString, scope: .library)
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
              item.displayState != DisplayStateMask.totalHidden.rawValue else { return }
        // Idempotent: a second pass over an already trashed item removed the tags twice.
        // See CODE_AUDIT_Folder §5.19.
        tagController.remove(tags: item.tags, module: itemControllable.config.module)
        item.displayState = DisplayStateMask.totalHidden.rawValue
        save(updated: item, message: String(localized: "Delete", bundle: .module).localizedString, forceSave: forceSave)
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
              item.displayState == DisplayStateMask.totalHidden.rawValue else { return }
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
                        save(updated: child, message: String(localized: "Restore parent", bundle: .module).localizedString)
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
                    save(updated: parentItem, message: String(localized: "Restore item", bundle: .module).localizedString)
                }
            }
        }

        tagController.add(tags: item.tags, module: itemControllable.config.module)
        item.displayState = DisplayStateMask.fullVisible.rawValue
        save(updated: item, message: String(localized: "Restore item", bundle: .module).localizedString)
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
        saveFolderEdit(item, message: String(localized: "Delete item", bundle: .module).localizedString, scope: .library)
    }

    @MainActor func moveItems(source: IndexSet, destination: Int, itemId: UUID) {
        guard let item = folderEditModel(for: itemId, scope: .library) else { return }
        var entries = item.entries
        entries.move(fromOffsets: source, toOffset: destination)
        item.entries = entries
        saveFolderEdit(item, message: String(localized: "Move entries", bundle: .module).localizedString, scope: .library)
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
    @MainActor func removeEntry(source: ItemRowModel, forceSave: Bool = false) {
        guard source.typeId == itemControllable.config.module, let entryId = source.entryId, let updatedModel = editModel(for: source.itemId) else { return }

        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Delete Entry", bundle: .module).localizedString, forceSave: forceSave)
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
        save(with: String(localized: "update from sync", bundle: .module).localizedString, currentModel: updated)
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

// MARK: - Undo / Redo

public extension EditControllable {
    @MainActor
    var canUndo: Bool {
        editorModel.undoManaged.canUndo
    }

    @MainActor
    var canRedo: Bool {
        editorModel.undoManaged.canRedo
    }

    @MainActor
    func undo() {
        // Undoing a folder edit made on the library: what redo brings back is the library's
        // state now, and it is a library edit as well. See CODE_AUDIT_21 §5.31.
        if let next = editorModel.undoManaged.nextUndoValue as? Model, editorModel.isLibraryScopedUndo(next),
           let current = itemControllable.itemSync(for: next.id, noGame: true)?.copy() {
            editorModel.markLibraryScopedUndo(current)
            editorModel.undoManaged.updateValue(current)
        }
        editorModel.undoManaged.undo()
        applyUndoValue()
    }

    @MainActor
    func redo() {
        if let next = editorModel.undoManaged.nextRedoValue as? Model, editorModel.isLibraryScopedUndo(next),
           let current = itemControllable.itemSync(for: next.id, noGame: true)?.copy() {
            editorModel.markLibraryScopedUndo(current)
            editorModel.undoManaged.updateValue(current)
        }
        editorModel.undoManaged.redo()
        applyUndoValue()
    }

    /// Writes the value undo or redo just restored. A folder edit made on the library goes
    /// back to the library: through `replace` with its default it only reached game memory
    /// during a game, and the library kept the move. See CODE_AUDIT_21 §5.31.
    @MainActor
    private func applyUndoValue() {
        guard let model = editorModel.undoManaged.value as? Model else { return }
        if editorModel.isLibraryScopedUndo(model) {
            itemControllable.persistMembershipChange(model: model)
        } else {
            itemControllable.replace(model: model, isInsert: false)
        }
        editorModel.cacheItemListModel.reset(itemId: model.id)
    }

    @MainActor
    var undoTitle: String {
        editorModel.undoManaged.undoTitles.last ?? ""
    }

    @MainActor
    var redoTitle: String {
        editorModel.undoManaged.redoTitles.last ?? ""
    }
}
