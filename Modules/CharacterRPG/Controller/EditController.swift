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
    var childIds: [UUID: UUID] = [:]

    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    let selectionTable: ItemSelectionModel = ItemSelectionModel()
}

public struct LinkCharacterModuleTransferable: LinkDataTransferable {
    public var module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .characterLink)
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .tableLink)
    }
}

struct EditController: Sendable {
    @MainActor init(root: CharacterRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.root = root
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
                
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        
        self.editorModel = ItemEditorModel()
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
}
 
// MARK: - EntryList editor

extension EditController {
    public var linkModules: [NetworkModules] { [.value, .dice, .pdf, .table] }
    
    public var additioanlEnrtryViewType: AdditionalEntryViewType { .inline }
    
    @MainActor public func additionalRowView(for source: ItemRowModel, textModel: LinkHighlightTextModel?) -> AnyView {
        AnyView(AddtionalEntryRow(source: source, textModel: textModel).equatable())
    }
    
    @MainActor private func addLinkInName(link: String, module: NetworkModules, itemId: UUID, entryId: UUID, destinationItemId: UUID, destinationEntryId: UUID) {
        guard let editModel = editModel(for: destinationItemId) else { return }
        var entry = editModel[destinationEntryId]
        
        let entryLink = "/\(entryId.uuidString)"
        let linkText = " [\(link)](\(URL.appScheme)://\(module.token)/0/\(itemId.uuidString)\(entryLink))"
        entry.name = linkText
        editModel[destinationEntryId] = entry
        save(updated: editModel, message: String(localized: "Add Link").localizedString)
    }
    
    @MainActor public func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID) {
        guard canAddLink(module: module, entryId: entryId), let item = editModel(for: destinationItemId) else { return }
        
        switch module {
        case .table:
            if let entryId {
                addLinkInName(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId,  destinationEntryId: destinationEntryId)
            }
        case .dice:
            var entry = item[destinationEntryId]
            entry.diceId = itemId
            if entry.type != .number || entry.type != .decimal {
                entry.type = .number
            }
            item[destinationEntryId] = entry
            save(updated: item, message: String(localized: "Add Dice").localizedString)
        case .pdf:
            var entry = item[destinationEntryId]
            if entry.type != .text {
                entry.type = .text
                item[destinationEntryId] = entry
                save(updated: item, message: String(localized: "Change Value Type").localizedString)
            }
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
        case .value:
            var entry = item[destinationEntryId]
            if entry.type != .number || entry.type != .decimal {
                entry.type = .number
                item[destinationEntryId] = entry
                save(updated: item, message: String(localized: "Change Value Type").localizedString)
            }
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId, separator: "+")
        default:
            return
        }
    }
    
    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        (module == .value && entryId != nil) || module == .dice || module == .pdf || (module == .table && entryId != nil)
    }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        EditorRoute.linkSelection(itemRowModel)
    }
    
    public func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination {
        switch module {
        case .dice:
            SelectionDiceRoute.selection
        default:
            SelectionTableRoute.selection
        }
    }
    
    @MainActor public func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String {
        guard let item = editModel(for: itemId) else { return "" }
        return root.linkController.linkText(model: item, entryId: entry.id)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessable) async {
        _ = await itemController.duplicate(itemId: item.id)
    }
    
    @MainActor func add(selection: [WindowItemSelection], itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let photos = Set(editModel.photos)
        var newPhotos = Set(selection.map { $0.itemId })
        newPhotos.subtract(photos)
        editModel.photos.append(contentsOf: newPhotos)
        editModel.photoId = editModel.photos.first
        save(updated: editModel, message: String(localized: "Change Photo").localizedString)
    }
    
    @MainActor func add(diceId: UUID?, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.diceId = diceId
        save(updated: editModel, message: String(localized: "Change Dice").localizedString)
        //root.gameController.resetGameDiceId(itemId: model.id, entryId: entryId)
    }
}

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: .text, value: content)
    }
}

// GameController

extension EditController {
    @MainActor func add(model childModel: ValueModel, into itemId: UUID?) {
        guard let itemId else { return }
        let entry = ValueEntryModel(id: UUID(), name: "", type: .text, value: "", valueId: childModel.id)
        add(entry: entry, into: itemId)
    }
}

// MARK: - Quick Row Edit

extension EditController {
    @MainActor func addEntry(itemId: UUID, after entryId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let newEntry = ValueEntryModel.empty(UUID())
        let index = (editModel.entries.firstIndex(where: { $0.id == entryId }) ?? 0) + 1
        add(entry: newEntry, into: itemId, index: index)
    }

    @MainActor func remove(itemId: UUID, entryId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        remove(entryId: entryId, from: item)
        save(updated: item, message: String(localized: "Remove entry").localizedString)
    }

    // deep delete after didDelete
    @MainActor func remove(entryId: UUID, from item: ValueModel, isDeepRemove: Bool = false) {
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = item.entries[index]
        item.entries.remove(at: index)
        if let valueId = entry.valueId {
            if isDeepRemove == true {
                let subValue = itemController.itemOrEmpty(for: valueId)
                guard subValue.isGroupHidden else { return }
                delete(itemId: valueId)
            } else {
                removeChild(childId: valueId)
            }
        }
    }

    @MainActor
    func toggleSelected(itemId: UUID, entryId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel[entryId].toggleSelection()
        if editModel[entryId].valueSelected {
            for entry in editModel.entries {
                guard entry.id != entryId && entry.type == .selection && entry.valueSelected else { continue }
                editModel[entry.id].toggleSelection()
            }
        }
        save(updated: editModel, message: String(localized: "Changed selection").localizedString)
    }

    @MainActor
    func toggleType(itemId: UUID, entryId: UUID, updatedValue: ValueEntryModel.ValueType) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel[entryId].type = updatedValue
        save(updated: editModel, message: String(localized: "Change type").localizedString)
    }

    @MainActor
    func updateDecimal(itemId: UUID, entryId: UUID, value: Double) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].valueDecimal != value {
            editModel[entryId].valueDecimal = value
            save(updated: editModel, message: String(localized: "Update decimal").localizedString)
        }
    }

    @MainActor
    func updateNumber(itemId: UUID, entryId: UUID, value: Int) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].valueNumber != value {
            editModel[entryId].valueNumber = value
            save(updated: editModel, message: String(localized: "Update number").localizedString)
        }
    }

    @MainActor
    func updateValue(itemId: UUID, entryId: UUID, value: String) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].value != value {
            editModel[entryId].value = value
            save(updated: editModel, message: String(localized: "Update value").localizedString)
        }
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
    func createGroup(itemId: UUID, entryIds: [UUID]) {
        guard let item = editModel(for: itemId) else { return }
        guard entryIds.count > 0, item.entries.count > 0, var groupIndex = item.entries.firstIndex(where: { $0.id == entryIds[0] }) else { return }
        let valueEntryIndice = entryIds.compactMap { entryId -> Int? in
            item.entries.firstIndex(where: { $0.id == entryId })
        }
        let valueEntries = valueEntryIndice.sorted().map { item.entries[$0] }
        valueEntryIndice.sorted(by: >).forEach { item.entries.remove(at: $0) }

        groupIndex = min(max(groupIndex, 0), item.entries.count)

        let newValue = ValueModel(id: UUID(), name: "\(item.name) \(String(localized: "Group").localizedString)", description: item.description, tags: item.tags, category: item.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: item.photoId, photos: item.photos, entries: valueEntries)
        let newEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", diceId: nil, valueId: newValue.id)
        newValue.parentId = item.id

        item.entries.insert(newEntry, at: groupIndex)
        itemController.replace(model: newValue, isInsert: true, shouldRepairLinks: true)
        save(updated: item, message: String(localized: "Created group").localizedString)
    }

    @MainActor
    func ungroup(from itemId: UUID, entryIds: [UUID]) async {
        for entryId in entryIds {
            await ungroup(itemId: itemId, entryId: entryId)
        }
    }

    @MainActor
    func toggleGroup(for rootModel: ItemRowModel, models: [ItemRowModel]) async {
        guard let editModel = editModel(for: rootModel.itemId) else { return }
        // root is an entry
        if let entryId = rootModel.entryId {
            // is grouped
            if let groupId = editModel[entryId].valueId {
                // ungrouping
                await ungroup(groupId: groupId, from: entryId, into: editModel.id)
            } else {
                await group(itemId: editModel.id, entryId: entryId, models: models)
            }
        } else {
            await group(itemId: editModel.id, entryId: nil, models: models)
        }
    }

    @MainActor
    func setGroupPhotos(itemId: UUID) async {
        guard let editModel = editModel(for: itemId) else { return }
        let allGroupIds = valueGroupIds(value: editModel)
        for allGroupId in allGroupIds {
            guard allGroupId != editModel.id, let value = itemController.copy(of: allGroupId) else { return }
            value.photoId = editModel.photoId
            value.photos = editModel.photos
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
    private func ungroup(itemId: UUID, entryId: UUID) async {
        guard let editModel = editModel(for: itemId) else { return }
        guard let groupIndex = editModel.entries.firstIndex(where: { $0.id == entryId }), let valueId = editModel[entryId].valueId else { return }
        let valueGroupped = itemController.itemOrEmpty(for: valueId)
        let groupEntries = valueGroupped.entries
        editModel.entries.remove(at: groupIndex)
        await itemController.delete(itemId: valueId)
//        for entry in groupEntries {
//            remove(entryId: entry.id, from: valueGroupped, isDeepRemove: true)
//        }
        groupEntries.reversed().forEach {
            editModel.entries.insert($0, at: groupIndex)
        }
        save(updated: editModel, message: String(localized: "Insert group").localizedString)
    }

    @MainActor
    private func group(itemId: UUID, entryId: UUID?, models: [ItemRowModel]) async {
        guard let editModel = editModel(for: itemId) else { return }

        var entries: [ValueEntryModel] = []
        for model in models {
            if let entryId = model.entryId, let valueModel = await itemController.item(for: model.itemId) {
                let entry = valueModel[entryId]
                entries.append(entry)
            }
        }
        if let entryId {
            entries.insert(editModel[entryId], at: 0)
        }

        let value = ValueModel(id: UUID(), name: entries.first?.name ?? String(localized: "Unnamed").localizedString, description: "", tags: editModel.tags, category: editModel.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: editModel.photoId, photos: editModel.photoId != nil ? [editModel.photoId!] : [], entries: entries)
        itemControllable.replace(model: value, isInsert: true, shouldRepairLinks: true)

        let valueEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", valueId: value.id)

        if let entryId {
            if let index = editModel.entries.firstIndex(where: { $0.id == entryId }) {
                editModel.entries.insert(valueEntry, at: index)
            }
            for entry in entries {
                if let index = editModel.entries.firstIndex(where: { $0.id == entry.id }) {
                    editModel.entries.remove(at: index)
                }
            }
        } else {
            editModel.entries.append(valueEntry)
        }
        save(updated: editModel, message: String(localized: "Grouped").localizedString)
    }

    @MainActor
    private func ungroup(groupId: UUID, from entryId: UUID, into itemId: UUID) async {
        guard let editModel = editModel(for: groupId) else { return }
        guard let item = self.editModel(for: itemId) else { return }
        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
            item.entries.insert(contentsOf: editModel.entries, at: index)
        } else {
            item.entries.append(contentsOf: editModel.entries)
        }
        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
            item.entries.remove(at: index)
        }
        await itemController.delete(itemId: groupId)
        for entry in editModel.entries {
            remove(entryId: entry.id, from: editModel, isDeepRemove: true)
        }
        save(updated: item, message: String(localized: "Ungrouped").localizedString)
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
    func addChild(childId: UUID?, into itemId: UUID, entryId: UUID) {
        guard canAddChild(childId: childId) else { return }
        guard let parent = editModel(for: itemId) else { return }
        if let existingChildId = parent[entryId].valueId {
            // save is missing
            itemController.itemOrEmpty(for: existingChildId).parentId = nil
        }
        parent[entryId].valueId = childId
        if let childId {
            // save is missing
            itemController.itemOrEmpty(for: childId).parentId = itemId
        }
        save(updated: parent, message: String(localized: "Add child item").localizedString)
    }

    @MainActor
    func removeChild(childId: UUID?) {
        guard let childId, let parentId = itemController.itemOrEmpty(for: childId).parentId else { return }
        let child = itemController.itemOrEmpty(for: childId).copy()
        child.parentId = nil
        itemController.replace(model: child, isInsert: false, shouldRepairLinks: true)
        guard let parent = editModel(for: parentId) else { return }
        let entries = parent.entries.map {
            var entry = $0
            if entry.valueId == childId {
                entry.valueId = nil
            }
            return entry
        }
        parent.entries = entries
        save(updated: parent, message: String(localized: "Remove child item").localizedString)
    }

    func copyAddChild(childId: UUID, into itemId: UUID, entryId: UUID) async {
        let copiedChildId = await itemController.duplicate(itemId: childId)
        await addChild(childId: copiedChildId, into: itemId, entryId: entryId)
    }
}

// MARK: - Selection

extension EditController {
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

extension EditController {
    @MainActor
    func merge(itemId: UUID, entries: [ValueEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.value = entry.value
            return foundEntry ?? entry
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = itemController.config.module
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
            save(updated: item, message: String(localized: "Entries replaced").localizedString)
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
