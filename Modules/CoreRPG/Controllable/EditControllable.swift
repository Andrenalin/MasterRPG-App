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
    @MainActor internal var model: Model {
        get { editorModel.undoManaged.value as? Model ?? .empty }
        nonmutating set {
            // it is a class an updated already
        }
    }

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
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.category != category else { return }
        editModel.category = category
        save(updated: editModel, message: String(localized: "Change to \(category.title)").localizedString)
    }

    @MainActor func reset(description: String, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.description != description else { return }
        editModel.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: model.id, text: model.description.markDownText())
        save(updated: editModel, message: String(localized: "Typing").localizedString)
    }
    
    @MainActor func reset(displayState: Int, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.displayState != displayState else { return }
        editModel.displayState = displayState
        save(updated: editModel, message: String(localized: "Change Display").localizedString)
    }

    @MainActor func reset(name: String, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.name != name else { return }
        editModel.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
        save(updated: editModel, message: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(tags: [String], itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard editModel.tags != sortedTags else { return }
        editModel.tags = sortedTags
        save(updated: editModel, message: String(localized: "Changed tags").localizedString)
    }
    
    @MainActor func reset(hidden: Bool, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.isGroupHiddenToggle != hidden else { return }
        editModel.isGroupHiddenToggle = hidden
        save(updated: editModel, message: String(localized: "Change to \(hidden ? "hide" : "show")").localizedString)
    }

    @MainActor func reset(fileUrl: FileUrl?, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard editModel.fileUrl != fileUrl else { return }
        editModel.fileUrl = fileUrl
        save(updated: editModel, message: String(localized: "Change file").localizedString)
    }

    @MainActor func add(tag: String, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        guard !tag.isEmpty else { return }
        guard !editModel.tags.contains(where: { $0 == tag }) else { return }
        var tags = editModel.tags
        tags.append(tag)
        editModel.tags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        save(updated: editModel, message: String(localized: "Add \(tag)").localizedString)
    }

    @MainActor func remove(tag: String, itemId: UUID) {
        guard var editModel = editModel(for: itemId) else { return }
        var tags = model.tags
        guard let index = tags.firstIndex(of: tag) else { return }
        tags.remove(at: index)
        editModel.tags = tags
        save(updated: editModel, message: String(localized: "Remove \(tag)").localizedString)
    }
}

// MARK: - Group Items / Carousell Items

public extension EditControllable {
    @MainActor func addGroup(itemId: UUID, childId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard editModel.id != childId && editModel.hasEntry(entryId: childId) == false else { return }
        let childItem = itemControllable.itemOrEmpty(for: childId)
        guard childItem.category != .folder && childItem.category != itemControllable.collectionCategory  else { return }
        var entries = editModel.entries

        let entry =  Model.Entry.newChild(id: childId)
        entries.append(entry)
        editModel.entries = entries

        reset(displayState: 1, itemId: childId)
        save(updated: editModel, message: String(localized: "Add groupped item").localizedString)
    }

    @MainActor func removeGroup(itemId: UUID, childId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard editModel.id != childId else { return }
        var entries = editModel.entries
        entries.removeAll(where: { $0.childId == childId })
        editModel.entries = entries
        
        reset(displayState: 0, itemId: childId)
        save(updated: editModel, message: String(localized: "Remove groupped item").localizedString)
    }
}

// MARK: - Folder / Colllection

public extension EditControllable {
    @MainActor func addItem(itemId: UUID, parentId: UUID?) {
        guard let parentId, itemId != parentId, let parentModel = editModel(for: parentId), var item = editModel(for: itemId) else { return }
        if item.specialCategory && !parentModel.isFolder {
            return
        }
        if parentModel.isFolder && item.parentId == parentId {
            return
        }
        if parentModel.isFolder && item.parentId != nil {
            removeItemFromParent(itemId: itemId)
        }
        let entry = Model.Entry.newChild(id: itemId)
        var entries = parentModel.entries
        if parentModel.category == .folder {
            entries.removeAll { $0.childId == itemId }
        }
        entries.append(entry)
        if parentModel.category == .folder {
            entries = entries.sorted {
                let name1 = itemControllable.nameSync(itemId: $0.childId)
                let name2 = itemControllable.nameSync(itemId: $1.childId)
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }
        }

        if parentModel.category == .folder {
            item.parentId = parentModel.id
            save(updated: item, message: String(localized: "Added parent").localizedString)
        }

        parentModel.entries = entries
        save(updated: parentModel, message: String(localized: "Added item").localizedString)
    }
    
    @MainActor func removeItemFromParent(itemId: UUID) {
        guard var item = editModel(for: itemId), let parentId = item.parentId, let parentModel = editModel(for: parentId) else { return }
        item.parentId = nil
        save(updated: item, message: String(localized: "Removed parent").localizedLowercase.localizedString)

        var entries = parentModel.entries
        entries.removeAll(where: { $0.childId == itemId })
        parentModel.entries = entries
        save(updated: parentModel, message: String(localized: "Removed item").localizedLowercase.localizedString)
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
    
    @MainActor func removeItem(offsets: IndexSet, item: any ItemDataAccessable) {
        guard let updatedModel = editModel(for: item.id) else { return }
        let removedEntries = updatedModel.entries.enumerated().filter { offsets.contains($0.offset) }
        var entries = updatedModel.entries
        entries.remove(atOffsets: offsets)
        updatedModel.entries = entries
        
        if updatedModel.category == .folder {
            for (_, entry) in removedEntries {
                delete(itemId: entry.childId)
            }
        }
        save(updated: updatedModel, message: String(localized: "Delete item").localizedString)
    }
    
    @MainActor func moveItems(source: IndexSet, destination: Int, item: any ItemDataAccessable) {
        guard let updatedModel = editModel(for: item.id) else { return }
        var entries = updatedModel.entries
        entries.move(fromOffsets: source, toOffset: destination)
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Move entries").localizedString)
    }
}

// MARK: - New Entry Editor

public extension EditControllable {
    @MainActor func removeEntry(source: ItemRowModel) {
        guard source.typeId == itemControllable.config.module else { return }
        guard let model = itemControllable.itemSync(for: source.itemId), let entryId = source.entryId else { return }
        remove(entryId: entryId, item: model)
    }
}

public extension EditControllable {
    @MainActor func insert(entry: any EntryDataAccessable, item: any ItemDataAccessable) {
        guard let updatedModel = editModel(for: item.id) else { return }
        guard let entry = entry as? Model.Entry else { return }
        var entries = updatedModel.entries
        entries.append(entry)
        updatedModel.entries = entries
        save(updated: updatedModel, message: String(localized: "Append Entry").localizedString)
    }
    
    @MainActor func remove(entry indexSet: IndexSet, item: any ItemDataAccessable) {
        guard let updatedModel = editModel(for: item.id) else { return }
        var entries = updatedModel.entries
        entries.remove(atOffsets: indexSet)
        updatedModel.entries = entries
        
        save(updated: updatedModel, message: String(localized: "Delete Entries").localizedString)
    }
    
    @MainActor func remove(entryId: UUID, item: any ItemDataAccessable) {
        guard let updatedModel = editModel(for: item.id) else { return }
        var entries = updatedModel.entries
        entries.removeAll(where: { $0.id == entryId})
        updatedModel.entries = entries
        
        save(updated: updatedModel, message: String(localized: "Delete Entry").localizedString)
    }
}

// MARK: - Files

public extension EditControllable {
    func resetFile(url: URL?, itemId: UUID) {
        guard fileUrlDataController != nil else { return }
        Task.detached {
            await resetFile(url: url, itemId: itemId)
        }
    }
    
    func moved(oldName: String) async {
        guard let fileUrlDataController else { return }
        let oldFileUrl = await model.fileUrl
        let newName = await model.name
        let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: newName)
        if let newFileUrl {
            await reset(fileUrl: newFileUrl, itemId: model.id)
        }
    }
    
    private func resetFile(url: URL?, itemId: UUID) async {
        guard let fileUrlDataController, let editModel = await editModel(for: itemId) else { return }
        await fileUrlDataController.delete(model.fileUrl)
        guard let url else {
            await reset(fileUrl: nil, itemId: itemId)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if editModel.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await reset(name: name, itemId: itemId)
        }
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: itemId, url: url, module: itemControllable.config.module.token, category: model.category.title)
        await reset(fileUrl: updatedFileUrl, itemId: itemId)
    }
    
    func resetFile(data: Data?, itemId: UUID, path: String) async throws {
        guard let itemModel = await editModel(for: itemId) else { return }
        if itemModel.fileUrl != nil {
            await resetFile(url: nil, itemId: itemId)
        }
        guard let data else { return }
        
        let module = itemControllable.config.module.token
        let filePath = itemModel.name.isEmpty ? "\(path)NewData-\(itemModel.id.uuidString).\(itemControllable.config.filenameExtension)" : "\(path)\(itemModel.name).\(itemControllable.config.filenameExtension)"
        var dataFileUrl = await FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: itemControllable.config.filenameExtension)
        
        guard var editModel = await editModel(for: itemId) else { return }
        editModel.fileUrl = fileUrl
        await save(updated: editModel, message: String(localized: "New File").localizedString)
    }

}

// MARK: - controller mantainence

public extension EditControllable {
    func didDelete(itemId: UUID) async {
        guard await editorModel.currentItemId == itemId else { return }
        await editorModel.reset()
    }

    func didUpdate(item: Model) async {
        guard await editorModel.currentItemId == item.id else { return }
        await setModel(await model.merge(item))
    }

    @MainActor func setModel(_ update: Model) {
        guard !model.isEqual(other: update) else { return }
        editorModel.undoManaged.updateValue(update)
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
        save(with: "")
        editorModel.reset()

        editorModel.undoManaged.resetValue(model)
        editorModel.currentItemId = model.id
        editorModel.currentEntryId = entryId
    }

    @MainActor func resetCurrentItem(with title: String) {
        save(with: title)
        editorModel.reset()
    }

    @MainActor func save(with name: String) {
        guard editorModel.currentItemId != nil, let currentModel = editorModel.currentModel as? Model else { return }
        validateBeforeSave(model: currentModel)
        guard !itemControllable.isEqual(with: currentModel) else { return }
        saveChanges(to: currentModel, name: name)
    }

    func update(itemId: UUID) async {
        guard await itemId == model.id, let updated = await itemControllable.item(for: model.id) as? Model else { return }
        _ = await model.replace(with: updated)
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
        itemControllable.replace(model: editorModel.undoManaged.value, isInsert: false, shouldRepairLinks: true)
        editorModel.cacheItemListModel.reset(itemId: model.id)
    }

    @MainActor
    func redo() {
        editorModel.undoManaged.redo()
        itemControllable.replace(model: editorModel.undoManaged.value, isInsert: false, shouldRepairLinks: true)
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

// MARK: - General Edit

extension EditControllable {
    @MainActor public func editModel(for itemId: UUID) -> Model? {
        guard model.id != itemId else { return model }
        return itemControllable.itemSync(for: itemId)?.copy() as? Model
    }

    @MainActor private func saveChanges(to newValue: Model, name: String) {
        editorModel.undoManaged.previousValue(itemControllable.itemOrEmpty(for: newValue.id).copy(), title: name)
        itemControllable.replace(model: newValue, isInsert: false, shouldRepairLinks: true)
    }

    @MainActor public func save(updated: Model, message: String) {
        if updated.id == model.id {
            save(with: message)
        } else {
            itemControllable.replace(model: updated, isInsert: false, shouldRepairLinks: false)
        }
    }
}

