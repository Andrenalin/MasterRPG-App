// @copyright André Trettin

import Observation
import SwiftUI

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ModelType

    var itemControllable: any ItemControllable { get }
    var fileUrlDataController: FileUrlDataController? { get }
    @MainActor var linkRegisterControllable: LinkRegisterControllable { get }

    var editorModel: ItemEditorModel { get }

    // overwrite extensions
    @MainActor func duplicate(item: any ItemDataAccessable) async
    @MainActor func validateBeforeSave(model: Model)
}

public extension EditControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }
    
//    @MainActor internal var model: Model {
//        get { editorModel.undoManaged.value as? Model ?? .empty }
//        nonmutating set {
//            // it is a class an updated already
//        }
//    }

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
        save(updated: item, message: String(localized: "Change to \(category.title)").localizedString)
    }

    @MainActor func reset(description: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.description != description else { return }
        item.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: item.id, text: item.description.markDownText())
        save(updated: item, message: String(localized: "Typing").localizedString)
    }
    
    @MainActor func reset(displayState: Int, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.displayState != displayState else { return }
        item.displayState = displayState
        save(updated: item, message: String(localized: "Change Display").localizedString)
    }

    @MainActor func reset(name: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.name != name else { return }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: item.id, text: item.name.markDownText())
        save(updated: item, message: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(tags: [String], itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard item.tags != sortedTags else { return }
        item.tags = sortedTags
        save(updated: item, message: String(localized: "Changed tags").localizedString)
    }
    
    @MainActor func reset(hidden: Bool, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.isGroupHiddenToggle != hidden else { return }
        item.isGroupHiddenToggle = hidden
        save(updated: item, message: String(localized: "Change to \(hidden ? "hide" : "show")").localizedString)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard item.fileUrl != fileUrl else { return }
        item.fileUrl = fileUrl
        save(updated: item, message: String(localized: "Change file").localizedString)
    }

    @MainActor func add(tag: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        guard !tag.isEmpty else { return }
        guard !item.tags.contains(where: { $0 == tag }) else { return }
        var tags = item.tags
        tags.append(tag)
        item.tags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        save(updated: item, message: String(localized: "Add \(tag)").localizedString)
    }

    @MainActor func remove(tag: String, itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        var tags = item.tags
        guard let index = tags.firstIndex(of: tag) else { return }
        tags.remove(at: index)
        item.tags = tags
        save(updated: item, message: String(localized: "Remove \(tag)").localizedString)
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
        save(updated: item, message: String(localized: "Add groupped item").localizedString)
    }

    @MainActor func removeGroup(itemId: UUID, childId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.id != childId else { return }
        var entries = item.entries
        entries.removeAll(where: { $0.childId == childId })
        item.entries = entries
        
        reset(displayState: 0, itemId: childId)
        save(updated: item, message: String(localized: "Remove groupped item").localizedString)
    }
}

// MARK: - Folder / Colllection

public extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?) {
        guard let parentId, itemId != parentId, let parentItem = editModel(for: parentId), var item = editModel(for: itemId) else { return }
        if item.specialCategory && !parentItem.isFolder {
            return
        }
        if parentItem.isFolder && item.parentId == parentId {
            return
        }
        if parentItem.isFolder && item.parentId != nil {
            removeItemFromParent(itemId: itemId)
        }
        let entry = Model.Entry.newChild(id: itemId)
        var entries = parentItem.entries
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

        if parentItem.category == .folder {
            item.parentId = parentItem.id
            save(updated: item, message: String(localized: "Added parent").localizedString)
        }

        parentItem.entries = entries
        save(updated: parentItem, message: String(localized: "Added item").localizedString)
    }
    
    @MainActor func removeItemFromParent(itemId: UUID) {
        guard var item = editModel(for: itemId), let parentId = item.parentId, let parentItem = editModel(for: parentId) else { return }
        item.parentId = nil
        save(updated: item, message: String(localized: "Removed parent").localizedLowercase.localizedString)

        var entries = parentItem.entries
        entries.removeAll(where: { $0.childId == itemId })
        parentItem.entries = entries
        save(updated: parentItem, message: String(localized: "Removed item").localizedLowercase.localizedString)
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
                    entryItem.parentId = item.parentId // upper folder
                }
                entryItem.displayState = 0
                save(updated: entryItem, message: String(localized: "Remove parent").localizedString)
            }
        }
        item.displayState = 2
        save(updated: item, message: String(localized: "Delete").localizedString)
    }
    
    @MainActor func duplicate(item: any ItemDataAccessable) async {
        guard let model = itemControllable.itemSync(for: item.id) else { return }
        let duplicate = model.duplicate()
        // character dupplicate
        itemControllable.replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
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
        item.displayState = 2
        save(updated: item, message: String(localized: "Delete").localizedString)
    }
    
    @MainActor func restore(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        for entry in item.entries {
            if var entryItem = editModel(for: entry.childId) {
                if item.category == .folder {
                    entryItem.parentId = item.id // to this folder
                }
                entryItem.displayState = 1 // hidden
                save(updated: entryItem, message: String(localized: "Restore parent").localizedString)
            }
        }
        item.displayState = 0
        save(updated: item, message: String(localized: "Restore item").localizedString)
    }
    
    @MainActor func removeItem(offsets: IndexSet, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let removedEntries = item.entries.enumerated().filter { offsets.contains($0.offset) }
        var entries = item.entries
        entries.remove(atOffsets: offsets)
        item.entries = entries
        
        if item.category == .folder {
            for (_, entry) in removedEntries {
                delete(itemId: entry.childId)
            }
        }
        save(updated: item, message: String(localized: "Delete item").localizedString)
    }
    
    @MainActor func moveItems(source: IndexSet, destination: Int, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        var entries = item.entries
        entries.move(fromOffsets: source, toOffset: destination)
        item.entries = entries
        save(updated: item, message: String(localized: "Move entries").localizedString)
    }
}

// MARK: - New Entry Editor

public extension EditControllable {
    @MainActor func removeEntry(source: ItemRowModel) {
        guard source.typeId == itemControllable.config.module, let entryId = source.entryId, let updatedModel = editModel(for: source.itemId) else { return }
        
        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Delete Entry").localizedString)
    }
}

// MARK: - Files

public extension EditControllable {
    func folderPath(itemId: UUID?) async -> String {
        guard let itemId, let item = await editModel(for: itemId) else { return "" }
        if let parentId = item.parentId {
            return await folderPath(itemId: parentId) + "/"
        }
        return item.name
    }
    
    func moved(oldName: String, itemId: UUID) async {
        guard let fileUrlDataController, let item = await editModel(for: itemId) else { return }
        let oldFileUrl = item.fileUrl
        let newName = item.name
        let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: newName)
        if let newFileUrl {
            await reset(fileUrl: newFileUrl, itemId: item.id)
        }
    }
    
    func resetFile(url: URL?, itemId: UUID) async {
        guard let fileUrlDataController, let item = await editModel(for: itemId) else { return }
        if item.fileUrl != nil {
            await cacheItemListModel.resetImageCache(itemId: itemId)
            await itemControllable.cacheControllable?.remove(itemId: itemId)
            fileUrlDataController.delete(item.fileUrl)
            await reset(fileUrl: nil, itemId: itemId)
        }
        guard let url else { return }
        
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
        editorModel.undoManaged.previousValue(itemControllable.itemOrEmpty(for: newValue.id).copy(), title: name)
        itemControllable.replace(model: newValue, isInsert: false, shouldRepairLinks: true)
    }

    @MainActor func save(updated: Model, message: String) {
        save(with: message, currentModel: updated)
    }

    @MainActor func setCurrentItem(to item: ItemRowTreeModel) {
        guard editorModel.currentItemId != item.model.itemId else {
            editorModel.currentEntryId <=> item.model.entryId
            return
        }
        guard let model = itemControllable.copy(of: item.model.itemId) as? Model else { return }
        setCurrentItem(model: model, entryId: item.model.entryId)
    }
    
    @MainActor func setCurrentItem(model: Model, entryId: UUID? = nil) {
        //editorModel.reset()
        editorModel.cacheItemListModel.resetItemLink()
        editorModel.undoManaged.resetValue(model)
        editorModel.currentItemId = model.id
        editorModel.currentEntryId = entryId
    }

    @MainActor func save(with name: String, currentModel: Model) {
        //guard editorModel.currentItemId != nil else { return }
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
            itemControllable.replace(model: model, isInsert: false, shouldRepairLinks: true)
            editorModel.cacheItemListModel.reset(itemId: model.id)
        }
    }

    @MainActor
    func redo() {
        editorModel.undoManaged.redo()
        if let model = editorModel.undoManaged.value as? Model {
            itemControllable.replace(model: model, isInsert: false, shouldRepairLinks: true)
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
