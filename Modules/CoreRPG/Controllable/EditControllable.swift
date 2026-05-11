// @copyright André Trettin

import Observation
import SwiftUI

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ItemLinkRegistable & ModelType

    var itemControllable: any ItemControllable { get }
    var fileUrlDataController: FileUrlDataController? { get }
    @MainActor var linkRegisterController: LinkRegisterController { get }
    var tagController: TagController { get }
    
    var editorModel: ItemEditorModel { get }
    @MainActor var sheetEditorModel: SheetEditorModel { get }

    // overwrite extensions
    @MainActor func duplicate(item: any ItemDataAccessable) async
    @MainActor func validateBeforeSave(model: Model)
}

public extension EditControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }
    
    @MainActor var cacheItemListModel: CacheItemListModel {
        editorModel.cacheItemListModel
    }

    @MainActor func validateBeforeSave(model: Model) {}
}

// MARK: - Editor Basic Properties

public extension EditControllable {
    @MainActor func update(id: UUID, name: String, description: String, category: ItemListCategory, tags: [String]) {
        reset(name: name, itemId: id)
        reset(description: description, itemId: id)
        reset(name: name, itemId: id)
        reset(category: category, itemId: id)
        reset(tags: tags, itemId: id)
    }

    @MainActor func reset(category: ItemListCategory, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.category != category else { return }
        item.category = category
        save(updated: item, message: String(localized: "Change to \(category.title)", bundle: .module).localizedString)
    }

    @MainActor func reset(description: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.description != description else { return }
        item.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module).localizedString)
    }
    
    @MainActor func reset(displayState: Int, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.displayState != displayState else { return }
        item.displayState = displayState
        save(updated: item, message: String(localized: "Change Display", bundle: .module).localizedString)
    }

    @MainActor func reset(name: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.name != name else { return }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
        save(updated: item, message: String(localized: "Typing", bundle: .module).localizedString)
    }

    @MainActor func reset(tags: [String], itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard item.tags != sortedTags else { return }
        let addedTags = Array(Set(sortedTags).subtracting(item.tags))
        let removedTags = Array(Set(item.tags).subtracting(sortedTags))
        updateTags(addedTags: addedTags, removedTags: removedTags)
        item.tags = sortedTags
        save(updated: item, message: String(localized: "Changed tags", bundle: .module).localizedString)
    }
    
    @MainActor func reset(hidden: Bool, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.isGroupHiddenToggle != hidden else { return }
        item.isGroupHiddenToggle = hidden
        save(updated: item, message: String(localized: "Change to \(hidden ? "hide" : "show")", bundle: .module).localizedString)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.fileUrl != fileUrl else { return }
        item.fileUrl = fileUrl
        save(updated: item, message: String(localized: "Change file", bundle: .module).localizedString)
    }

    @MainActor func add(tag: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard !tag.isEmpty else { return }
        guard !item.tags.contains(where: { $0 == tag }) else { return }
        var tags = item.tags
        tags.append(tag)
        updateTags(addedTags: [tag], removedTags: [])
        item.tags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        save(updated: item, message: String(localized: "Add \(tag)", bundle: .module).localizedString)
    }

    @MainActor func remove(tag: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        var tags = item.tags
        guard let index = tags.firstIndex(of: tag) else { return }
        tags.remove(at: index)
        item.tags = tags
        updateTags(addedTags: [], removedTags: [tag])
        save(updated: item, message: String(localized: "Remove \(tag)", bundle: .module).localizedString)
    }
    
    @MainActor private func updateTags(addedTags: [String], removedTags: [String]) {
        tagController.add(tags: addedTags, module: itemControllable.config.module)
    }
}

// MARK: - Other

public extension EditControllable {
    @MainActor func repairFolder(itemId: UUID) {
        guard let item = editModel(for: itemId), item.parentId != nil else { return }
        for id in itemControllable.itemDataModel.items {
            guard id != item.parentId, let checkItem = itemControllable.itemSync(for: id), checkItem.isFolder else { continue }
            guard let index = checkItem.entries.firstIndex(where: { $0.childId == itemId }) else { return }
            guard let folderItem = editModel(for: id) else { return }
            folderItem.entries.remove(at: index)
            save(updated: folderItem, message: String(localized: "removed item from folder", bundle: .module).localizedString)
        }
        guard item.entries.isEmpty else { return }
    }
}

// MARK: - Group Items / Carousell Items

public extension EditControllable {
    @MainActor func addGroup(itemId: UUID, childId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId && item.hasEntry(entryId: childId) == false else { return }
        let childItem = itemControllable.itemOrEmpty(for: childId)
        guard childItem.category != .folder && childItem.category != itemControllable.collectionCategory  else { return }
        var entries = item.entries

        let entry =  Model.Entry.newChild(id: childId)
        entries.append(entry)
        item.entries = entries

        reset(displayState: 1, itemId: childId)
        save(updated: item, message: String(localized: "Add groupped item", bundle: .module).localizedString)
    }

    @MainActor func removeGroup(itemId: UUID, childId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId else { return }
        var entries = item.entries
        entries.removeAll(where: { $0.childId == childId })
        item.entries = entries
        
        reset(displayState: 0, itemId: childId)
        save(updated: item, message: String(localized: "Remove groupped item", bundle: .module).localizedString)
    }
}

// MARK: - Folder / Colllection

public extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?) {
        guard let parentId, itemId != parentId, let parentItem = editModel(for: parentId), var item = editModel(for: itemId) else { return }
        if (parentItem.isFolder && parentItem.category == .item) && item.parentId == parentId {
            return
        }
        if parentItem.isFolder && item.parentId != nil {
            removeItemFromParent(itemId: itemId, oneUp: false, moveFiles: false)
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
            entries.append(entry)
            if parentItem.category == .folder {
                entries = entries.sorted {
                    let name1 = itemControllable.nameSync(itemId: $0.childId)
                    let name2 = itemControllable.nameSync(itemId: $1.childId)
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            }
        }
        
        if parentItem.category == .folder || parentItem.category == .item {
            item.parentId <=> parentItem.id
            if parentItem.category == .item {
                item.displayState <=> 1
            }
            save(updated: item, message: String(localized: "Added parent", bundle: .module).localizedString)
            movedFile(itemId: itemId)
        }

        if parentItem.category != .item {
            parentItem.entries <=> entries
        }
        save(updated: parentItem, message: String(localized: "Added item", bundle: .module).localizedString)
    }

    @MainActor func remove(itemId: UUID, parentId: UUID, oneUp: Bool) {
        guard let parentItem = editModel(for: parentId) else { return }
        if parentItem.isFolder {
            removeItemFromParent(itemId: itemId, oneUp: oneUp)
        } else {
            var entries = parentItem.entries
            entries.removeAll(where: { $0.childId == itemId })
            parentItem.entries = entries
            save(updated: parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString)
        }
    }

    @MainActor func removeItemFromParent(itemId: UUID, oneUp: Bool, moveFiles: Bool = true) {
        guard var item = editModel(for: itemId), let parentId = item.parentId, let parentItem = editModel(for: parentId) else { return }
        item.parentId = nil
        save(updated: item, message: String(localized: "Removed parent", bundle: .module).localizedLowercase.localizedString)
            
        var entries = parentItem.entries
        entries.removeAll(where: { $0.childId == itemId })
        parentItem.entries = entries
        save(updated: parentItem, message: String(localized: "Removed item", bundle: .module).localizedLowercase.localizedString)
        
        guard oneUp && parentItem.parentId != nil else {
            if moveFiles {
                movedFile(itemId: itemId)
            }
            return
        }
        addItem(itemId: itemId, parentId: parentItem.parentId)
    }
    
    @MainActor func cleanFolder(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.entries.removeAll {
            let child = itemControllable.itemOrEmpty(for: $0.childId)
            if child.parentId != itemId {
                return true
            }
            return false
        }
        save(updated: item, message: String(localized: "update folder", bundle: .module).localizedString)
    }
}

// MARK: - Collect Items for Removal

public extension EditControllable {
    @MainActor func markCollectionItemsForRemoval(for items: [ItemRowModel]) -> [ItemRowModel] {
        var allRemovingItems = items
        var processedIds = Set<UUID>()

        func collectChildren(from itemModels: [ItemRowModel]) {
            for itemModel in itemModels {
                guard !processedIds.contains(itemModel.itemId) else { continue }
                processedIds.insert(itemModel.itemId)

                if let model = itemControllable.itemSync(for: itemModel.itemId), model.isFolder {
                    // Only folders delete their children, so only add folder children to the removing list
                    let children = model.entries.map {
                        ItemRowModel(itemId: $0.childId, typeId: itemModel.typeId)
                    }
                    allRemovingItems.append(contentsOf: children)
                    // Recursively collect children from nested folders
                    collectChildren(from: children)
                }
            }
        }

        collectChildren(from: items)
        
        allRemovingItems.forEach {
            markForDeletion(itemId: $0.itemId)
        }
        return allRemovingItems
    }
}

// MARK: - Menu

public extension EditControllable {
    func addNew(type: EditControllerAddType) async -> (any ItemDataAccessable)? {
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
    
    @MainActor func delete(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.displayState != 2 else {
            // real delete
            Task {
                await itemControllable.delete(itemId: itemId)
            }
            return
        }
        for entry in item.entries {
            if var entryItem = editModel(for: entry.childId) {
                if item.category == .folder {
                    entryItem.parentId = item.parentId // move to upper folder (or root if nil)
                    entryItem.displayState = 2 // mark children as deleted when folder is deleted
                } else {
                    entryItem.displayState = 0 // for non-folder containers, reset to visible
                }
                save(updated: entryItem, message: String(localized: "Remove parent", bundle: .module).localizedString)
            }
        }
        
        tagController.remove(tags: item.tags, module: itemControllable.config.module)
        linkRegisterController.repairLinks(for: [ItemRowModel(itemId: itemId, typeId: itemControllable.config.module)])
        linkRegisterController.resetUsedLink(for: ItemRowModel(itemId: itemId, typeId: itemControllable.config.module))
        for entry in item.entries {
            linkRegisterController.resetUsedLink(for: ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemControllable.config.module))
        }

        item.displayState = 2
        save(updated: item, message: String(localized: "Delete", bundle: .module).localizedString)
    }
    
    @MainActor func duplicate(item: any ItemDataAccessable) async {
        guard let model = itemControllable.itemSync(for: item.id) else { return }
        let duplicate = model.duplicate()
        // character dupplicate
        itemControllable.replace(model: duplicate, isInsert: true)
        if let fileUrl = model.fileUrl, let fileUrlDataController, let data = try? await fileUrlDataController.loadData(for: fileUrl) {
            var path = fileUrl.rawUrl.deletingLastPathComponent().path(percentEncoded: false)
            if path == "./" {
                path = ""
            }
            try? await resetFile(data: data, itemId: duplicate.id, path: path)
        }
    }
    
    @MainActor func markForDeletion(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        tagController.remove(tags: item.tags, module: itemControllable.config.module)
        item.displayState = 2
        save(updated: item, message: String(localized: "Delete", bundle: .module).localizedString)
    }
    
    @MainActor func restore(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }

        // If this is a folder being restored, restore its children
        if item.category == .folder {
            for entry in item.entries {
                if var entryItem = editModel(for: entry.childId) {
                    entryItem.parentId = item.id // to this folder
                    entryItem.displayState = 1 // hidden
                    save(updated: entryItem, message: String(localized: "Restore parent", bundle: .module).localizedString)
                }
            }
        } else {
            // If this is a child being restored, check if its parent folder still exists and is not deleted
            if let parentId = item.parentId, let parentItem = editModel(for: parentId), parentItem.displayState == 2 {
                // Parent folder is deleted, move child to root level
                item.parentId = nil
            }
        }

        tagController.add(tags: item.tags, module: itemControllable.config.module)
        item.displayState = 0
        save(updated: item, message: String(localized: "Restore item", bundle: .module).localizedString)
    }
    
    @MainActor func removeItem(offsets: IndexSet, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let removedEntries = item.entries.enumerated().filter { offsets.contains($0.offset) }
        var entries = item.entries
        entries.remove(atOffsets: offsets)
        item.entries = entries

        if item.category == .folder {
            // For folders, move children to root level (set parentId = nil) instead of deleting them
            for (_, entry) in removedEntries {
                if var childItem = editModel(for: entry.childId) {
                    childItem.parentId = nil
                    save(updated: childItem, message: String(localized: "Removed parent", bundle: .module).localizedLowercase.localizedString)
                }
            }
        }
        // For non-folder containers (collections), just remove from entries (no need to modify children)
        save(updated: item, message: String(localized: "Delete item", bundle: .module).localizedString)
    }
    
    @MainActor func moveItems(source: IndexSet, destination: Int, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        var entries = item.entries
        entries.move(fromOffsets: source, toOffset: destination)
        item.entries = entries
        save(updated: item, message: String(localized: "Move entries", bundle: .module).localizedString)
    }
}

// MARK: - New Entry Editor

public extension EditControllable {
    @MainActor func removeEntry(source: ItemRowModel) {
        guard source.typeId == itemControllable.config.module, let entryId = source.entryId, let updatedModel = editModel(for: source.itemId) else { return }
        
        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Delete Entry", bundle: .module).localizedString)
    }
}

// MARK: - Files

public extension EditControllable {
    func folderPath(itemId: UUID?) async -> String {
        guard let itemId, let item = await editModel(for: itemId) else { return "" }
        var name = ""
        if let parentId = item.parentId {
            name = await folderPath(itemId: parentId) + "/"
        }
        name.append(item.name)
        return name
    }
    
    func movedFile(itemId: UUID) {
        Task {
            guard let fileUrlDataController, let item = await editModel(for: itemId), let oldFileUrl = item.fileUrl else { return }
            let path = await folderPath(itemId: itemId)
            let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, to: path)
            if let newFileUrl {
                await reset(fileUrl: newFileUrl, itemId: item.id)
            }
        }
    }
    
    func resetFile(url: URL?, itemId: UUID) async {
        guard let fileUrlDataController, let item = await editModel(for: itemId) else { return }

        // Check if we have an existing file
        var isSameFilePath: Bool = false
        if let existingFileUrl = item.fileUrl {
            // If selecting same file, just reset cache without deleting
            isSameFilePath = await fileUrlDataController.isSameFile(existingFileUrl: existingFileUrl, newUrl: url)
            // reset cach only for the thumbnail, it might be old thumbnail file exists.
            await cacheItemListModel.resetImageCache(itemId: itemId, includeImage: !isSameFilePath)
            await itemControllable.cacheControllable?.remove(itemId: itemId, includeImage: !isSameFilePath)

            if !isSameFilePath {
                // Different file - delete old file and clear reference
                fileUrlDataController.delete(existingFileUrl)
                await reset(fileUrl: nil, itemId: itemId)
            }
        }

        guard let url, !isSameFilePath else { return }

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if item.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await reset(name: name, itemId: itemId)
        }

        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: itemId, url: url, module: itemControllable.config.module.token, category: folderPath(itemId: item.parentId))
        await reset(fileUrl: updatedFileUrl, itemId: itemId)
    }
    
    func resetFile(data: Data?, itemId: UUID, path: String) async throws {
        guard let item = await editModel(for: itemId) else { return }
        if item.fileUrl != nil {
            await resetFile(url: nil, itemId: itemId)
        }
        guard let data else { return }
        
        let module = itemControllable.config.module.token
        var folder = await folderPath(itemId: item.parentId)
        if !folder.isEmpty {
            folder.append("/")
        }
        let filePath = item.name.isEmpty ? "\(folder)NewData-\(item.id.uuidString).\(itemControllable.config.filenameExtension)" : "\(folder)\(item.name).\(itemControllable.config.filenameExtension)"
        var dataFileUrl = FileUrl(fileId: item.id, url: URL(string: filePath)!, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataFileUrl, pathExtension: itemControllable.config.filenameExtension)
        await reset(fileUrl: fileUrl, itemId: itemId)
    }
}

// MARK: - controller mantainence

public extension EditControllable {
    @MainActor func editModel(for itemId: UUID) -> Model? {
        return itemControllable.itemSync(for: itemId)?.copy() as? Model
    }

    @MainActor func saveChanges(to newValue: Model, name: String) {
        if let previous = itemControllable.itemSync(for: newValue.id) as? Model {
            let (added, removed) = newValue.changedLinkRegisterModels(oldValue: previous)
            
            linkRegisterController.deregister(links: removed)
            linkRegisterController.register(links: added)
        } else {
            let added = newValue.linkRegisterModels
            linkRegisterController.register(links: added)
        }
        
        editorModel.undoManaged.previousValue(itemControllable.itemOrEmpty(for: newValue.id).copy(), title: name)
        itemControllable.replace(model: newValue, isInsert: false)
    }

    @MainActor func save(updated: any Observable) {
        guard let updated = updated as? Model else { return }
        save(with: String(localized: "update from sync", bundle: .module).localizedString, currentModel: updated)
    }

    @MainActor func save(updated: Model, message: String) {
        save(with: message, currentModel: updated)
    }

    @MainActor func setCurrentItem(to item: ItemRowTreeModel) {
        guard sheetEditorModel.itemId != item.model.itemId else {
            sheetEditorModel.entryId <=> item.model.entryId
            sheetEditorModel.module = item.model.typeId
            return
        }
        guard let model = itemControllable.copy(of: item.model.itemId) as? Model else { return }
        setCurrentItem(model: model, entryId: item.model.entryId, module: item.model.typeId)
    }
    
    @MainActor func setCurrentItem(model: Model, entryId: UUID? = nil, module: NetworkModules? = nil) {
        if model.id != sheetEditorModel.itemId {
            editorModel.cacheItemListModel.resetItemLink()
            editorModel.undoManaged.resetValue(model)
            sheetEditorModel.itemId = model.id
        }
        sheetEditorModel.entryId <=> entryId
        sheetEditorModel.module = module ?? itemControllable.config.module
    }

    @MainActor func save(with name: String, currentModel: Model) {
        validateBeforeSave(model: currentModel)
        guard !itemControllable.isEqual(with: currentModel) else { return }
        saveChanges(to: currentModel, name: name)
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
        editorModel.undoManaged.undo()
        if let model = editorModel.undoManaged.value as? Model {
            itemControllable.replace(model: model, isInsert: false)
            editorModel.cacheItemListModel.reset(itemId: model.id)
        }
    }

    @MainActor
    func redo() {
        editorModel.undoManaged.redo()
        if let model = editorModel.undoManaged.value as? Model {
            itemControllable.replace(model: model, isInsert: false)
            editorModel.cacheItemListModel.reset(itemId: model.id)
        }
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
