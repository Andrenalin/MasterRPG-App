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
    var rootControllable: any RootControllable { get }

    var editorModel: ItemEditorModel { get }


    @MainActor
    var model: Model { get set }

    // reset / edit  extensions
    @MainActor func reset(name: String, saveIt: Bool)
    @MainActor func reset(category: ItemListCategory, saveIt: Bool)
    @MainActor func reset(description: String, saveIt: Bool)
    @MainActor func reset(hidden: Bool)
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
    @MainActor func update(name: String, description: String, category: ItemListCategory, tags: [String]) {
        reset(name: name, saveIt: false)
        reset(description: description, saveIt: false)
        reset(name: name, saveIt: false)
        reset(category: category, saveIt: false)
        reset(tags: tags, saveIt: false)

        save(with: String(localized: "Changed Header").localizedString)
    }

    @MainActor func reset(category: ItemListCategory, saveIt: Bool = true) {
        guard model.category != category else { return }
        model.category = category
        guard saveIt else { return }
        save(with: String(localized: "Change to \(category.title)").localizedString)
    }

    @MainActor func reset(description: String, saveIt: Bool = true) {
        guard model.description != description else { return }
        model.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .description, itemId: model.id, text: model.description.markDownText())
        guard saveIt else { return }
        save(with: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(name: String, saveIt: Bool = true) {
        guard model.name != name else { return }
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
        guard saveIt else { return }
        save(with: String(localized: "Typing").localizedString)
    }

    @MainActor func reset(tags: [String], saveIt: Bool = true) {
        let sortedTags = tags.sorted(by: { $0.localizedCompare($1) == .orderedAscending })
        guard model.tags != sortedTags else { return }
        model.tags = sortedTags
        guard saveIt else { return }
        save(with: String(localized: "Changed tags").localizedString)
    }
    
    @MainActor func reset(hidden: Bool) {
        guard model.isGroupHiddenToggle != hidden else { return }
        model.isGroupHiddenToggle = hidden
        save(with: String(localized: "Change to \(hidden ? "hide" : "show")").localizedString)
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
        guard model.id != childId else { return }
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
//    func duplicate(item: ItemDataModel) {
//        duplicateDataModel(item: item, newItemId: UUID())
//    }
//
//    func duplicateDataModel(item: ItemDataModel, newItemId: UUID) {
//        let modelContext = itemControllable.container.mainContext
//        let duplicate = item.duplicate(newItemId: newItemId, url: nil)
//        modelContext.insert(duplicate)
//        try? modelContext.save()
//        guard let fileUrlDataController, let actor = duplicate.modelActor() else { return }
//        let originalFileUrl = item.fileUrl
//        Task.detached {
//            await actor.setup(id: newItemId)
//            guard let fileUrl = try? await fileUrlDataController.duplicate(fileUrl: originalFileUrl, for: newItemId) else { return }
//            await actor.update(url: fileUrl.rawUrl)
//            await actor.save()
//        }
//    }
}

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

    @MainActor
    func setModel(_ update: Model) {
        guard !model.isEqual(other: update) else { return }
        editorModel.undoManaged.updateValue(update)
    }

    @MainActor
    func setCurrentItem(to item: ItemRowTreeModel) {
        save(with: "")
        resetCurrentModel()
        editorModel.reset()

        guard let model = itemControllable.copy(of: item.model.itemId) as? Model else { return }
        editorModel.undoManaged.resetValue(model)
        editorModel.currentItemId = item.model.itemId
        editorModel.currentListItem = item
        editorModel.currentEntryId = item.model.entryId

        editorModel.nameTextFieldModel.text = model.name
        editorModel.categoryEditModel.selection = model.category
        editorModel.hiddenToggleModel.state = model.isGroupHidden
        editorModel.descriptionTextFieldModel.text = model.description

        didSetModel()
    }

    @MainActor
    func resetCurrentItem(with title: String) {
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

private extension EditControllable {
    @MainActor
    func saveChanges(to newValue: Model, name: String) {
        editorModel.undoManaged.previousValue(itemControllable.itemOrEmpty(for: newValue.id).copy(), title: name)
        itemControllable.replace(model: newValue, isInsert: false, shouldRepairLinks: true)
    }
}
