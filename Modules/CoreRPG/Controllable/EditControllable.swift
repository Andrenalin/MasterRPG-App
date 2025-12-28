// @copyright André Trettin

import Observation
import SwiftUI

public enum EditTypes: Equatable, Hashable {
    case main
    case link
    case module(NetworkModules)
}

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ModelType

    var itemControllable: any ItemControllable { get }
    var fileUrlDataController: FileUrlDataController? { get }
    @MainActor var linkRegisterControllable: LinkRegisterControllable { get }

    var editorModel: ItemEditorModel { get }

    @MainActor
    var model: Model { get set }

    // reset / edit  extensions
    @MainActor func reset(name: String, saveIt: Bool, modelId: UUID?)
    @MainActor func reset(category: ItemListCategory, saveIt: Bool, modelId: UUID?)
    @MainActor func reset(description: String, saveIt: Bool, modelId: UUID?)
    @MainActor func reset(hidden: Bool, modelId: UUID?)
    @MainActor func add(tag: String)
    @MainActor func remove(tag: String)

    // overwrite extensions
    @MainActor func resetCurrentModel()
    @MainActor func didSetModel()
    @MainActor func validateBeforeSave()
    @MainActor func validateEntries()
    @MainActor func submitChanges()
    @MainActor func save(with name: String)

    // selection edits
    @MainActor func selection(for module: NetworkModules) -> [ItemRowModel]
    @MainActor func toggle(for module: NetworkModules, itemRowModel: ItemRowModel) async
}

public extension EditControllable {
    @MainActor
    var model: Model {
        get { editorModel.undoManaged.value as? Model ?? .empty }
        nonmutating set {
            // it is a class an updated already
        }
    }

    @MainActor var cacheItemListModel: CacheItemListModel {
        editorModel.cacheItemListModel
    }

    @MainActor func resetCurrentModel() {}
    @MainActor func didSetModel() {}
    @MainActor func validateBeforeSave() {}
    @MainActor func validateEntries() {}
    @MainActor func submitChanges() {}

    @MainActor func selection(for module: NetworkModules) -> [ItemRowModel] { [] }
    @MainActor func toggle(for module: NetworkModules, itemRowModel: ItemRowModel) async {}
}

// MARK: - Editor

public extension EditControllable {
    @MainActor func update(id: UUID, name: String, description: String, category: ItemListCategory, tags: [String]) {
        reset(name: name, modelId: id)
        reset(description: description, modelId: id)
        reset(name: name, modelId: id)
        reset(category: category, modelId: id)
        reset(tags: tags, modelId: id)
    }

    @MainActor func reset(category: ItemListCategory, saveIt: Bool = true, modelId: UUID? = nil) {
        guard var editModel = editModel(for: modelId ?? model.id) else { return }
        guard editModel.category != category else { return }
        editModel.category = category
        guard saveIt else { return }
        save(updated: editModel, message: String(localized: "Change to \(category.title)").localizedString)
    }

    @MainActor func reset(description: String, saveIt: Bool = true, modelId: UUID? = nil) {
        guard var editModel = editModel(for: modelId ?? model.id) else { return }
        guard editModel.description != description else { return }
        editModel.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: model.id, text: model.description.markDownText())
        guard saveIt else { return }
        save(updated: editModel, message: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(name: String, saveIt: Bool = true, modelId: UUID? = nil) {
        guard var editModel = editModel(for: modelId ?? model.id) else { return }
        guard editModel.name != name else { return }
        editModel.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
        guard saveIt else { return }
        save(updated: editModel, message: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(tags: [String], saveIt: Bool = true, modelId: UUID? = nil) {
        guard var editModel = editModel(for: modelId ?? model.id) else { return }
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard editModel.tags != sortedTags else { return }
        editModel.tags = sortedTags
        guard saveIt else { return }
        save(updated: editModel, message: String(localized: "Changed tags").localizedString)
    }
    
    @MainActor func reset(hidden: Bool, modelId: UUID? = nil) {
        guard var editModel = editModel(for: modelId ?? model.id) else { return }
        guard editModel.isGroupHiddenToggle != hidden else { return }
        editModel.isGroupHiddenToggle = hidden
        save(updated: editModel, message: String(localized: "Change to \(hidden ? "hide" : "show")").localizedString)
    }

    @MainActor func reset(fileUrl: FileUrl?, saveIt: Bool) {
        guard model.fileUrl != fileUrl else { return }
        model.fileUrl = fileUrl
        guard saveIt else { return }
        save(with: String(localized: "Change file").localizedString)
    }

    @MainActor func add(tag: String) {
        guard !tag.isEmpty else { return }
        guard !model.tags.contains(where: { $0 == tag }) else { return }
        var tags = model.tags
        tags.append(tag)
        model.tags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        save(with: String(localized: "Add \(tag)").localizedString)
    }

    @MainActor func remove(tag: String) {
        var tags = model.tags
        guard let index = tags.firstIndex(of: tag) else { return }
        tags.remove(at: index)
        model.tags = tags
        save(with: String(localized: "Remove \(tag)").localizedString)
    }
}

// MARK: - Group Items

public extension EditControllable {
    @MainActor func addGroup(childId: UUID) {
        guard model.id != childId && model.hasEntry(entryId: childId) == false else { return }
        var childItem = itemControllable.itemOrEmpty(for: childId)
        guard childItem.category != .folder && childItem.category != itemControllable.collectionCategory  else { return }
        var entries = model.entries

        let entry =  Model.Entry.newChild(id: childId)
        entries.append(entry)
        model.entries = entries

        childItem.displayState = 1
        save(with: String(localized: "Add groupped item").localizedString)
    }

    @MainActor func removeGroup(childId: UUID) {
        guard model.id != childId else { return }
        var entries = model.entries
        entries.removeAll(where: { $0.childId == childId })
        model.entries = entries
        
        var childItem = itemControllable.itemOrEmpty(for: childId)
        childItem.displayState = 0
        save(with: String(localized: "Remove groupped item").localizedString)
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
                guard let item1 = itemControllable.itemSync(for: $0.childId),
                      let item2 = itemControllable.itemSync(for: $1.childId) else { return true }
                return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
            }
        }

        parentModel.entries = entries

        if parentModel.category == .folder {
            item.parentId = parentModel.id
            save(updated: item, message: String(localized: "Added parent").localizedString)
        }
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
        let itemRowModel = await itemControllable.addNew(type: itemCategory.rawValue)
        return await itemControllable.item(for: itemRowModel.itemId)
    }
    
    @MainActor func delete(itemId: UUID) {
        guard var item = editModel(for: itemId) else { return }
        //        if let fileUrl = item.fileUrl, let fileUrlDataController = fileUrlDataController {
        //            fileUrlDataController.delete(fileUrl)
        //        } - file needs to be deleted if real delete comes
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
        await itemControllable.duplicate(model: ItemRowModel(itemId: item.id, typeId: itemControllable.config.module))
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
    func resetFile(url: URL?, module: NetworkModules) {
        guard fileUrlDataController != nil else { return }
        Task.detached {
            await resetFile(url: url, id: model.id, module: module)
        }
    }
    
    func moved(oldName: String) async {
        guard let fileUrlDataController else { return }
        let oldFileUrl = await model.fileUrl
        let newName = await model.name
        let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: newName)
        if let newFileUrl {
            await reset(fileUrl: newFileUrl, saveIt: true)
        }
    }
    
    private func resetFile(url: URL?, id: UUID, module: NetworkModules) async {
        guard let fileUrlDataController else { return }
        await fileUrlDataController.delete(model.fileUrl)
        guard let url else {
            await reset(fileUrl: nil, saveIt: true)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if await model.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await reset(name: name, saveIt: false)
        }
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: module.token, category: model.category.title)
        await reset(fileUrl: updatedFileUrl, saveIt: true)
    }
}

// MARK: - controller mantainence

public extension EditControllable {
    func didDelete(itemId: UUID) async {
        guard await editorModel.currentItemId == itemId else { return }
        await resetCurrentModel()
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
        resetCurrentModel()
        editorModel.reset()

        editorModel.undoManaged.resetValue(model)
        editorModel.currentItemId = model.id
        //editorModel.currentListItem = item
        editorModel.currentEntryId = entryId

        editorModel.nameTextFieldModel.text = model.name
        editorModel.categoryEditModel.selection = model.category
        editorModel.hiddenToggleModel.state = model.isGroupHidden
        editorModel.descriptionTextFieldModel.text = model.description

        didSetModel()
    }

    @MainActor func resetCurrentItem(with title: String) {
        save(with: title)
        resetCurrentModel()
        editorModel.reset()
    }

    @MainActor func save(with name: String) {
        guard editorModel.currentItemId != nil, let currentModel = editorModel.currentModel as? Model else { return }
        validateEntries()
        validateBeforeSave()
        guard !itemControllable.isEqual(with: currentModel) else { return }
        saveChanges(to: currentModel, name: name)
    }

    func update(modelId: UUID) async {
        guard await modelId == model.id, let updated = await itemControllable.item(for: model.id) as? Model else { return }
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

    @MainActor func resetSearch(_ text: String) {
        editorModel.searchText = text
        editorModel.cacheItemListModel.reset(search: text)
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

