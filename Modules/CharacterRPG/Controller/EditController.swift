// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import RegexBuilder
import SwiftUI
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG

@MainActor @Observable
final class ValueEditModel: Sendable {
    var nameLinks: [UUID: LinkReplaceController] = [:]
    var valueLinks: [UUID: LinkReplaceController] = [:]

    var childIds: [UUID: UUID] = [:]

    let photoSelectionModel = SelectionModel(id: UUID(), filter: .character)
    let pdfSelectionModel = SelectionModel(id: UUID(), filter: .all)

    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
    let selectionTable: ItemSelectionModel = ItemSelectionModel()
    
    func resetLinks() {
        nameLinks = [:]
        valueLinks = [:]
    }
}

struct EditController: Sendable {
    @MainActor init(root: CharacterRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
                
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel, categorySelection: itemController.itemDataModel.categoryTags.first ?? .all)
        self.valueEditModel = ValueEditModel()
    }

    let root: CharacterRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable

    let editorModel: ItemEditorModel
    let valueEditModel: ValueEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = ValueModel

    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }

    @MainActor
    func add(model childModel: ValueModel, into itemId: UUID?) {
        guard let itemId else { return }
        let entry = ValueEntryModel(id: UUID(), name: "", type: .text, value: "", valueId: childModel.id)
        add(entry: entry, into: itemId)
    }

    @discardableResult @MainActor func copy(entryId: UUID, shouldSave: Bool) -> UUID {
        var duplicate = model[entryId].duplicate()
        Task {
            if let subValueId = duplicate.valueId {
                let newId = await itemController.duplicate(itemId: subValueId)
                duplicate.valueId = newId
            }
            model.entries.append(duplicate)
            if shouldSave {
                let name = String(duplicate.name.prefix(16))
                save(with: String(localized: "Copy entry \(name)").localizedString)
            }
        }
        return duplicate.id
    }

    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId else { return }
        if valueEditModel.photoSelectionModel.id != id {
            valueEditModel.photoSelectionModel.id = id
            if valueEditModel.photoSelectionModel.currentValue != model.photoId {
                valueEditModel.photoSelectionModel.currentValue = model.photoId
            }
        }

        if valueEditModel.pdfSelectionModel.id != id {
            valueEditModel.pdfSelectionModel.id = id
        }
    }

    @MainActor
    func resetCurrentModel() {
        valueEditModel.resetLinks()
    }

    @MainActor
    func remove(entryId: UUID, shouldSave: Bool) {
        guard let index = model.entries.firstIndex(where: { $0.id == entryId }) else { return }
        removeChild(childId: model[entryId].valueId)
        model.entries.remove(at: index)
        if shouldSave {
            save(with: String(localized: "Remove entry").localizedString)
        }
    }

    @MainActor
    func submitChanges() {
        valueEditModel.resetLinks()
    }
}

// MARK: - Edit Entry
extension EditController {

    @MainActor func reset(entryId: UUID, type: ValueEntryModel.ValueType) {
        guard type != model[entryId].type else { return }
        model[entryId].valueTypeToggle = type
        save(with: String(localized: "Change to \(type.title)").localizedString)
    }
}

// MARK: - Quick Entry Edit

extension EditController {
    @MainActor
    func addEntry(itemId: UUID, after entryId: UUID) {
        let newEntry = ValueEntryModel.empty(UUID())
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        let index = (model.entries.firstIndex(where: { $0.id == entryId }) ?? 0) + 1
        add(entry: newEntry, into: itemId, index: index)
    }

    @MainActor
    func remove(entryId: UUID, at itemId: UUID) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        remove(entryId: entryId, from: model)
        if editorModel.currentItemId == itemId {
            save(with: String(localized: "Remove entry").localizedString)
        } else {
            itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
        }
    }

    // deep delete after didDelete
    @MainActor
    func remove(entryId: UUID, from item: ValueModel, isDeepRemove: Bool = false) {
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = item.entries[index]
        item.entries.remove(at: index)
        if model.id == item.id {
            remove(entryId: entryId, shouldSave: false)
        }
        if let valueId = entry.valueId {
            if isDeepRemove == true {
                let subValue = itemController.itemOrEmpty(for: valueId)
                guard subValue.isGroupHidden else { return }
                Task {
                    await itemController.delete(model: ItemRowModel(itemId: subValue.id, typeId: itemController.itemDataModel.networkModule))
                }
            } else {
                removeChild(childId: valueId)
            }
        }
    }

    @MainActor
    func toggleSelected(itemId: UUID, entryId: UUID) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        model[entryId].toggleSelection()
        if model[entryId].valueSelected {
            for entry in model.entries {
                guard entry.id != entryId && entry.type == .selection && entry.valueSelected else { continue }
                model[entry.id].toggleSelection()
            }
        }
        if editorModel.currentItemId == itemId {
            save(with: String(localized: "Change selection").localizedString)
        } else {
            itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
        }
    }

    @MainActor
    func toggleType(itemId: UUID, entryId: UUID, updatedValue: ValueEntryModel.ValueType) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        model[entryId].type = updatedValue
        if editorModel.currentItemId == itemId {
            save(with: String(localized: "Change type").localizedString)
        } else {
            itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
        }
    }

    @MainActor
    func updateDecimal(itemId: UUID, entryId: UUID, value: Double) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        if model[entryId].valueDecimal != value {
            model[entryId].valueDecimal = value
            if editorModel.currentItemId == itemId {
                save(with: String(localized: "Change selection").localizedString)
            } else {
                itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
            }
        }
    }

    @MainActor
    func updateNumber(itemId: UUID, entryId: UUID, value: Int) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        if model[entryId].valueNumber != value {
            model[entryId].valueNumber = value
            if editorModel.currentItemId == itemId {
                save(with: String(localized: "Change selection").localizedString)
            } else {
                itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
            }
        }
    }

    @MainActor
    func updateValue(itemId: UUID, entryId: UUID, value: String) {
        let model = editorModel.currentItemId == itemId ? self.model : (itemController.copy(of: itemId) ?? .empty)
        if model[entryId].value != value {
            model[entryId].value = value
            if editorModel.currentItemId == itemId {
                save(with: String(localized: "Change selection").localizedString)
            } else {
                itemController.replace(model: model, isInsert: false, shouldRepairLinks: true)
            }
        }
    }
}

// MARK: - Dice

extension EditController {
    @MainActor func removeDice(from entryId: UUID) {
        model[entryId].diceId = nil
        save(with: String(localized: "Remove dice").localizedString)
        root.gameController.resetGameDiceId(itemId: model.id, entryId: entryId)
    }
}

// MARK: - Group Edit

extension EditController {
    var groupEdit: Bool {
        true
    }

    @MainActor
    func groupTitle(for models: [ItemRowModel], rootModel: ItemRowModel?) -> LocalizedStringKey {
        guard let rootModel else { return "Group" }
        let item = itemController.itemOrEmpty(for: rootModel.itemId)
        let count = models.count
        if let entryId = rootModel.entryId {
            // is grouped
            if let groupId = item[entryId].valueId {
                return "Ungroup \"\(itemController.itemOrEmpty(for: groupId).name)\" into \(itemController.itemOrEmpty(for: groupId).entries.count) item"
            } else {
                return "Group \"\(item[entryId].name)\" with \(count) item"
            }
        } else {
            if item.entries.isEmpty {
                if count == 0 {
                    return "Group \"\(item.name)\""
                }
                return "Group \"\(item.name)\" with \(count) item"
            }
            return "Ungroup \"\(item.name)\" into \(item.entries.count) item"
        }
    }

    @MainActor
    func createGroup(from entryIds: [UUID]) {
        guard entryIds.count > 0, model.entries.count > 0, var groupIndex = model.entries.firstIndex(where: { $0.id == entryIds[0] }) else { return }
        let valueEntryIndice = entryIds.compactMap { entryId -> Int? in
            model.entries.firstIndex(where: { $0.id == entryId })
        }
        let valueEntries = valueEntryIndice.sorted().map { model.entries[$0] }
        valueEntryIndice.sorted(by: >).forEach { model.entries.remove(at: $0) }

        groupIndex = min(max(groupIndex, 0), model.entries.count)

        let newValue = ValueModel(id: UUID(), name: "\(model.name) \(String(localized: "Group").localizedString)", description: model.description, tags: model.tags, category: model.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: model.photoId, photos: model.photos, entries: valueEntries)
        let newEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", diceId: nil, valueId: newValue.id)
        newValue.parentId = model.id

        model.entries.insert(newEntry, at: groupIndex)
        itemController.replace(model: newValue, isInsert: true, shouldRepairLinks: true)
        save(with: String(localized: "Created group").localizedString)
    }

    @MainActor
    func ungroup(from entryIds: [UUID]) async {
        for entryId in entryIds {
            await ungroup(from: entryId)
        }
    }

    @MainActor
    func toggleGroup(for rootModel: ItemRowModel, models: [ItemRowModel]) async {
        let item = rootModel.itemId == editorModel.currentItemId ? model : itemController.itemOrEmpty(for: rootModel.itemId)

        // root is an entry
        if let entryId = rootModel.entryId {
            // is grouped
            if let groupId = item[entryId].valueId {
                // ungrouping
                await ungroup(groupId: groupId, from: entryId, into: item.id)
            } else {
                await group(itemId: item.id, entryId: entryId, models: models)
            }
        } else {
            await group(itemId: item.id, entryId: nil, models: models)
        }
    }

    @MainActor
    func setGroupPhotos() async {
        let allGroupIds = valueGroupIds(value: model)
        for allGroupId in allGroupIds {
            guard allGroupId != model.id, let value = itemController.copy(of: allGroupId) else { return }
            value.photoId = model.photoId
            value.photos = model.photos
            itemController.replace(model: value, isInsert: false, shouldRepairLinks: false)
        }
    }

    @MainActor
    func valueGroupIds(value: ValueModel) -> Set<UUID> {
        value.entries.reduce(Set<UUID>()) { groups, nextValue in
            var all = groups
            if let nextId = nextValue.valueId {
                if !all.contains(nextId) {
                    all.insert(nextId)
                    all.formUnion(valueGroupIds(value: itemController.itemOrEmpty(for: nextId)))
                }
            }
            return all
        }
    }

    @MainActor
    private func ungroup(from entryId: UUID) async {
        let currentItem = model
        guard let groupIndex = model.entries.firstIndex(where: { $0.id == entryId }), let valueId = currentItem[entryId].valueId else { return }
        let groupEntries = itemController.itemOrEmpty(for: valueId).entries
        currentItem.entries.remove(at: groupIndex)
        await itemController.delete(itemId: valueId)
        groupEntries.reversed().forEach {
            currentItem.entries.insert($0, at: groupIndex)
        }
        save(with: String(localized: "Insert group").localizedString)
    }

    @MainActor
    private func group(itemId: UUID, entryId: UUID?, models: [ItemRowModel]) async {
        let item = itemId == editorModel.currentItemId ? model : itemController.itemOrEmpty(for: itemId)

        var entries: [ValueEntryModel] = []
        for model in models {
            if let entryId = model.entryId, let valueModel = await itemController.item(for: model.itemId) {
                let entry = valueModel[entryId]
                entries.append(entry)
            }
        }
        if let entryId {
            entries.insert(item[entryId], at: 0)
        }

        let value = ValueModel(id: UUID(), name: entries.first?.name ?? String(localized: "Unnamed").localizedString, description: "", tags: item.tags, category: item.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: item.photoId, photos: item.photoId != nil ? [item.photoId!] : [], entries: entries)
        itemControllable.replace(model: value, isInsert: true, shouldRepairLinks: true)

        let valueEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", valueId: value.id)

        if let entryId {
            if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
                item.entries.insert(valueEntry, at: index)
            }
            for entry in entries {
                if let index = item.entries.firstIndex(where: { $0.id == entry.id }) {
                    item.entries.remove(at: index)
                }
            }
        } else {
            item.entries.append(valueEntry)
        }

        if itemId == editorModel.currentItemId {
            save(with: String(localized: "Group").localizedString)
        } else {
            itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }

    @MainActor
    private func ungroup(groupId: UUID, from entryId: UUID, into itemId: UUID) async {
        let groupedItem = groupId == editorModel.currentItemId ? model : itemController.itemOrEmpty(for: groupId)
        let item = itemId == editorModel.currentItemId ? model : itemController.itemOrEmpty(for: itemId)
        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
            item.entries.insert(contentsOf: groupedItem.entries, at: index)
        } else {
            item.entries.append(contentsOf: groupedItem.entries)
        }
        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
            item.entries.remove(at: index)
        }
        await itemController.delete(itemId: groupId)
        if itemId == editorModel.currentItemId {
            save(with: String(localized: "Ungroup").localizedString)
        } else {
            itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
}

// MARK: - Parent / Child Relation

extension EditController {
    @MainActor
    func canAddChild(childId: UUID?) -> Bool {
        guard let childId else { return true }
        return itemController.itemOrEmpty(for: childId).parentId == nil
    }

    @MainActor
    func addChild(childId: UUID?, into entryId: UUID) {
        guard canAddChild(childId: childId) else { return }
        if let existingChildId = model[entryId].valueId {
            itemController.itemOrEmpty(for: existingChildId).parentId = nil
        }
        model[entryId].valueId = childId
        if let childId {
            itemController.itemOrEmpty(for: childId).parentId = model.id
        }

        save(with: String(localized: "Add child item").localizedString)
    }

    @MainActor
    func removeChild(childId: UUID?) {
        guard let childId, let parentId = itemController.itemOrEmpty(for: childId).parentId else { return }
        let child = itemController.itemOrEmpty(for: childId).copy()
        child.parentId = nil
        itemController.replace(model: child, isInsert: false, shouldRepairLinks: true)
        let parent = model.id == parentId ? model : itemController.itemOrEmpty(for: parentId).copy()
        let entries = parent.entries.map {
            var entry = $0
            if entry.valueId == childId {
                entry.valueId = nil
            }
            return entry
        }
        parent.entries = entries
        if model.id == parentId {
            save(with: String(localized: "Remove child item").localizedString)
        } else {
            itemController.replace(model: parent, isInsert: false, shouldRepairLinks: true)
        }
    }

    func copyAddChild(childId: UUID, into entryId: UUID) async {
        let copiedChildId = await itemController.duplicate(itemId: childId)
        await addChild(childId: copiedChildId, into: entryId)
    }
}

// MARK: - Selection

extension EditController {
    @MainActor @ViewBuilder
    func selectDice(for entryId: UUID, linkKeyPath: WritableKeyPath<ValueModel, String>?, dismissAction: @escaping () -> Void) -> some View {
        if let linkKeyPath {
            diceRoot.viewController.viewSelect(root: diceRoot, filter: .all) {
                let text = self.model[keyPath: linkKeyPath]
                return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .dice) }
            } toggleSelection: { sel, _ in
                self.model[keyPath: linkKeyPath] = self.diceRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
                self.save(with: String(localized: "Change dice links").localizedString)
            } dismissAction: {
                dismissAction()
            }
        } else {
            selectDice(for: entryId, dismissAction: dismissAction)
        }
    }

    @MainActor
    func selectDice(for entryId: UUID, dismissAction: @escaping () -> Void) -> some View {
        diceRoot.viewController.viewSelect(root: diceRoot, filter: .all) {
            if let diceId = self.model[entryId].diceId {
                return [ItemRowModel(itemId: diceId, typeId: .dice)]
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if self.model[entryId].diceId == selection.itemId {
                self.model[entryId].diceId = nil
            } else {
                self.model[entryId].diceId = selection.itemId
            }
            self.save(with: String(localized: "Change dice link").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor @ViewBuilder
    func selectPdf(for entryId: UUID, linkKeyPath: WritableKeyPath<ValueModel, String>?, dismissAction: @escaping () -> Void) -> some View {
        if let linkKeyPath {
            pdfRoot.viewController.viewSelect(root: pdfRoot, filter: .all) {
                let text = self.model[keyPath: linkKeyPath]
                return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .pdf) }
            } toggleSelection: { sel, _ in
                self.model[keyPath: linkKeyPath] = self.pdfRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
                self.save(with: String(localized: "Change pdf links").localizedString)
            } dismissAction: {
                dismissAction()
            }
        }
    }

    @MainActor @ViewBuilder
    func selectTable(for entryId: UUID, linkKeyPath: WritableKeyPath<ValueModel, String>?, dismissAction: @escaping () -> Void) -> some View {
        if let linkKeyPath {
            tableRoot.viewController.viewSelect(root: tableRoot, filter: .all, isGroupHidden: false) {
                let text = self.model[keyPath: linkKeyPath]
                return self.model.links(for: text).compactMap {
                    guard $0.module == .table else { return nil }
                    return ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module)
                }
            } toggleSelection: { sel, _ in
                self.model[keyPath: linkKeyPath] = self.tableRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
                self.save(with: String(localized: "Change table links").localizedString)
            } dismissAction: {
                dismissAction()
            }
        }
    }

    @MainActor @ViewBuilder
    func selectValue(for entryId: UUID, linkKeyPath: WritableKeyPath<ValueModel, String>?, selectionModel: SelectionSheetLinkModel, dismissAction: @escaping () -> Void) -> some View {
        if let linkKeyPath {
            root.viewController.viewSelect(root: root, filter: .all, isGroupHidden: false, focus: rootCharacter(for: model.id)) {
                let text = self.model[keyPath: linkKeyPath]
                return self.model.links(for: text).compactMap {
                    guard $0.module == .value else { return nil }
                    return ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module)
                }
            } toggleSelection: { sel, _ in
                self.model[keyPath: linkKeyPath] = self.root.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
                self.save(with: String(localized: "Change value links").localizedString)
            } dismissAction: {
                dismissAction()
            }
        } else {
            selectValue(for: entryId, selectionModel: selectionModel, dismissAction: dismissAction)
        }
    }

    @MainActor
    func selectValue(for entryId: UUID, selectionModel: SelectionSheetLinkModel, dismissAction: @escaping () -> Void) -> some View {
        if let valueId = model[entryId].valueId {
            valueEditModel.childIds[entryId] = valueId
        } else {
            valueEditModel.childIds.removeValue(forKey: entryId)
        }
        selectionModel.entryId = entryId
        selectionModel.dismissedAction = {
            let childId = valueEditModel.childIds[selectionModel.entryId]
            if canAddChild(childId: childId) {
                addChild(childId: childId, into: selectionModel.entryId)
            } else {
                selectionModel.childId = childId
            }
        }

        return root.viewController.viewSelect(root: root, filter: .all, isGroupHidden: false) {
            if let valueId = self.valueEditModel.childIds[entryId] {
                return [ItemRowModel(itemId: valueId, typeId: .value)]
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if self.valueEditModel.childIds[entryId] == selection.itemId {
                self.valueEditModel.childIds.removeValue(forKey: entryId)
            } else {
                self.valueEditModel.childIds[entryId] = selection.itemId
            }
            self.save(with: String(localized: "Change value link").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor
    func selectTemplate(selectionModel: SelectionSheetLinkModel, dismissAction: @escaping () -> Void) -> some View {
        let selectionId = UUID()
        selectionModel.entryId = selectionId

        selectionModel.dismissedAction = {
            guard let childId = valueEditModel.childIds[selectionModel.entryId] else { return }

            selectionModel.generatorId = childId
        }
        return root.viewController.viewSelect(root: root, filter: .character, isGroupHidden: false, searchText: "Template") {
            if let valueId = self.valueEditModel.childIds[selectionId] {
                return [ItemRowModel(itemId: valueId, typeId: .value)]
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if self.valueEditModel.childIds[selectionId] == selection.itemId {
                self.valueEditModel.childIds.removeValue(forKey: selectionId)
            } else {
                self.valueEditModel.childIds[selectionId] = selection.itemId
            }
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor private func rootCharacter(for valueId: UUID) -> UUID {
        let allCharacters = itemController.itemDataModel.items.filter { !itemController.itemOrEmpty(for: $0).isGroupHidden && itemController.itemOrEmpty(for: $0).category == .character }.map { itemController.itemOrEmpty(for: $0) }
        let firstOne = allCharacters.first {
            $0.entries.first {
                first(entry: $0, with: valueId)
            } != nil
        }
        if let firstOne {
            return firstOne.id
        } else {
            return valueId
        }
    }

    @MainActor private func first(entry: ValueEntryModel, with valueId: UUID) -> Bool {
        if let childId = entry.valueId {
            if childId == valueId {
                return true
            } else {
                return itemController.itemOrEmpty(for: childId).entries.first {
                    first(entry: $0, with: valueId)
                } != nil
            }
        }
        return false

    }
}

// MARK: - Link Editor

extension EditController {
    @MainActor func nameEditLink(for entryId: UUID) -> LinkReplaceController {
        guard let controller = valueEditModel.nameLinks[entryId] else {
            let controller = LinkReplaceController {
                model[entryId].name
            } setter: {
                update(entryId: entryId, name: $0)
            }
            valueEditModel.nameLinks[entryId] = controller
            return controller
        }
        return controller
    }

    @MainActor
    func updateNameContent(_ content: String, for entryId: UUID) {
        if let contentLink = valueEditModel.nameLinks[entryId] {
            contentLink.editValue.wrappedValue = content
        } else {
            update(entryId: entryId, name: content)
        }
        save(with: String(localized: "Add link").localizedString)
    }

    @MainActor func update(entryId: UUID, name: String) {
        model[entryId].name = name
        editorModel.cacheItemListModel.reset(cacheType: .entryName, itemId: entryId, text: name)
        let linkText = root.linkController.linkText(model: model, entryId: entryId)
        editorModel.cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: linkText)
    }

    @MainActor func contentEditLink(for entryId: UUID) -> LinkReplaceController {
        guard let controller = valueEditModel.valueLinks[entryId] else {
            let controller = LinkReplaceController {
                model[entryId].value
            } setter: {
                update(entryId: entryId, value: $0)
            }
            valueEditModel.valueLinks[entryId] = controller
            return controller
        }
        return controller
    }

    @MainActor
    func updateValueContent(_ content: String, for entryId: UUID) {
        if let contentLink = valueEditModel.valueLinks[entryId] {
            contentLink.editValue.wrappedValue = content
        } else {
            update(entryId: entryId, value: content)
        }
        save(with: String(localized: "Add link").localizedString)
    }

    @MainActor func update(entryId: UUID, value: String) {
        model[entryId].value = value
        let valueText = root.linkController.linkText(model: model, entryId: entryId, withoutName: true)
        editorModel.cacheItemListModel.reset(cacheType: .content, itemId: entryId, text: valueText)
        let linkText = root.linkController.linkText(model: model, entryId: entryId)
        editorModel.cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: linkText)
    }
}

// MARK: - LinkText

extension EditController {
    @MainActor
    func nameText(for entryId: ValueEntryModel.ID) -> String {
        var otherValue = ""
        if let valueId = model[entryId].valueId {
            otherValue = itemController.itemOrEmpty(for: valueId).url(linkNumber: 0)
        }

        if let diceId = model[entryId].diceId {
            if otherValue.isEmpty {
                otherValue = diceRoot.linkController.generateLink(itemId: diceId)
            } else {
                otherValue = "\(otherValue), \(diceRoot.linkController.generateLink(itemId: diceId))"
            }
        }

        return model[entryId].nameText(otherValue: " \(otherValue)")
    }
}

extension EditController {
    @MainActor
    func merge(entries: [ValueEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        let item = model
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.value = entry.value
            return foundEntry ?? entry
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = itemController.itemDataModel.networkModule
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.id, entryId: $0, typeId: module) }

        var effectedLinks = true
        for itemRowModel in itemRowModels {
            if !itemController.usedLinks(for: itemRowModel).isEmpty {
                effectedLinks = false
                break;
            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(with: String(localized: "Entries replaced").localizedString)
            return []
        }
        return itemRowModels
    }

    @MainActor
    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [ValueEntryModel] {
        guard let anotherIds else {
            let otherEntries: [LinkEntryModel]
            switch module {
                case .dice:
                    otherEntries = diceRoot.linkController.link(for: .table)
                case .table:
                    otherEntries = tableRoot.linkController.link(for: .value)
                default:
                    otherEntries = root.linkController.link(for: .value)
            }
            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
        }

        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
            switch module {
                case .dice:
                    return diceRoot.linkController.linkEntries(for: anotherId)
                case .table:
                    return tableRoot.linkController.linkEntries(for: anotherId)
                case .value:
                    return root.linkController.linkEntries(for: anotherId)
                default:
                    return []
            }
        }
        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
    }

    @MainActor func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [ValueEntryModel] {
        guard let entries = itemController.itemSync(for: itemId)?.entries else { return [] }
        return entries.map { entry in
            var replacedEntry = entry
            linkEntries.forEach { linkEntry in
                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.value }, setLink: { var result = $1; result.value = $0; return result }, caseInsensitive: caseInsensitive, words: words)

                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.name }, setLink: { var result = $1; result.name = $0; return result }, caseInsensitive: caseInsensitive, words: words)
            }
            return replacedEntry
        }
    }
}
