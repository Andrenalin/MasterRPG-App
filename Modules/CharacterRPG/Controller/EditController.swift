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
    @MainActor init(root: CharacterRootModel, itemController: ItemController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.root = root
                
        self.itemController = itemController
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        
        self.editorModel = ItemEditorModel()
        self.sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        self.valueEditModel = ValueEditModel()
    }

    let root: CharacterRootModel

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController

    let editorModel: ItemEditorModel
    let sheetEditorModel: SheetEditorModel
    let valueEditModel: ValueEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = ValueModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
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
        save(updated: editModel, message: String(localized: "Add Link", bundle: .module).localizedString)
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
            save(updated: item, message: String(localized: "Add Dice", bundle: .module).localizedString)
        case .pdf:
            var entry = item[destinationEntryId]
            if entry.type != .text {
                entry.type = .text
                item[destinationEntryId] = entry
                save(updated: item, message: String(localized: "Change Value Type", bundle: .module).localizedString)
            }
            addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
        case .value:
            var entry = item[destinationEntryId]
            if entry.type != .number || entry.type != .decimal {
                entry.type = .number
                item[destinationEntryId] = entry
                save(updated: item, message: String(localized: "Change Value Type", bundle: .module).localizedString)
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
    
    @MainActor public func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String {
        guard let item = editModel(for: itemId) else { return "" }
        return root.linkController.linkText(model: item, entryId: entry.id)
    }
    
    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return [] }
        return item.entries.compactMap {
            guard $0.id != sourceEntryId, let valueId = $0.valueId else { return nil }
            return FolderRepresentable(id: valueId, name: $0.name)
        }
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? {
        guard let item = itemControllable.itemSync(for: itemId) as? Model, let parentId = item.parentId else { return nil }
        guard let parent = itemControllable.itemSync(for: parentId) as? Model else { return nil }
        return FolderRepresentable(id: parent.id, name: parent.name)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessable) async {
        _ = await duplicate(itemId: item.id, withCopy: true)
    }
    
    func duplicate(itemId: UUID, withCopy: Bool) async -> UUID {
        let (duplicates, copyId, mapper) = await duplicateSubValue(id: itemId, withCopy: withCopy)
        await root.linkController.repairDuplicateLinks(models: duplicates, mapper: mapper)
        for duplicate in duplicates {
            // this will not add the links to the database linkregister is missing
            await itemController.replace(model: duplicate, isInsert: true)
        }
        return copyId
    }

    @MainActor
    private func duplicateSubValue(id: UUID, withCopy: Bool) -> ([ValueModel], UUID, [UUID: UUID]) {
        guard let item = itemController.itemSync(for: id) else { return ([], id, [:]) }
        
        var duplicates: [ValueModel] = []
        let copyItem: ValueModel = withCopy ? item.duplicate() : item.duplicateWithoutCopy()
        duplicates.append(copyItem)
        
        var mapper: [UUID: UUID] = [id: copyItem.id]
        let subValueIds = item.duplicateSubValueIds()
        subValueIds.forEach {
            let (newDuplicates, newCopyId, newMapper) = duplicateSubValue(id: $0, withCopy: false)
            mapper[$0] = newCopyId
            mapper.merge(newMapper) { first, _ in return first }
            duplicates.append(contentsOf: newDuplicates)
        }
        for (index, entry) in copyItem.entries.enumerated() {
            guard let valueId = entry.valueId else { continue }
            if let copyId = mapper[valueId] {
                copyItem.entries[index].valueId = copyId
                duplicates.first(where: { $0.id == copyId })?.parentId = copyItem.id
            }
        }
        return (duplicates, copyItem.id, mapper)
    }
    
    @MainActor func add(selection: [WindowItemSelection], itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photos <=> selection.map { $0.itemId }
        item.photoId <=> item.photos.first
        save(updated: item, message: String(localized: "Change Photo", bundle: .module).localizedString)
    }
    
    @MainActor func add(diceId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.diceId = diceId
        save(updated: item, message: String(localized: "Change Dice", bundle: .module).localizedString)
        //root.gameController.resetGameDiceId(itemId: model.id, entryId: entryId)
    }
    
    @MainActor func removePhotos(itemId: UUID) async {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = nil
        item.photos.removeAll()
        save(updated: item, message: String(localized: "remove photos", bundle: .module).localizedString)
    }

    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        let groupId = await itemController.addNew(type: .item)
        reset(hidden: true, itemId: groupId)
        guard let group = editModel(for: groupId) else { return groupId }
        group.parentId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.valueId = groupId
        add(entry: entry, itemId: itemId)
        return entry.id
    }
    
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String) {
        guard let item = editModel(for: itemId) else { return }
        if item[entryId].type == .text, parseDouble(from: content) != nil {
            item[entryId].type = parseInteger(from: content) == nil ? .decimal : .number
            save(updated: item, message: String(localized: "update value type", bundle: .module).localizedString)
        }
        updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: true)
        guard let valueId = item[entryId].valueId else { return }
        let fixedName = name.withoutLink()
        reset(name: fixedName, itemId: valueId)
        reset(description: content, itemId: valueId)
    }

    private func parseDouble(from string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        return formatter.number(from: trimmed)?.doubleValue
    }

    private func parseInteger(from string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        return formatter.number(from: trimmed)?.intValue
    }
}

// MARK: - Inline Quick Editor

extension EditController {
    @MainActor func entryValue(itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return "" }
        return itemController.itemOrEmpty(for: itemId)[entryId].value
    }
    
    @MainActor func entryValueAsDecimal(itemId: UUID, entryId: UUID?) -> Double {
        guard let entryId else { return 0.0 }
        return itemController.itemOrEmpty(for: itemId)[entryId].valueDecimal
    }
    
    @MainActor func entryValueAsNumber(itemId: UUID, entryId: UUID?) -> Int {
        guard let entryId else { return 0 }
        return itemController.itemOrEmpty(for: itemId)[entryId].valueNumber
    }
    
    @MainActor func entryValueAsSelected(itemId: UUID, entryId: UUID?) -> Bool {
        guard let entryId else { return false }
        return itemController.itemOrEmpty(for: itemId)[entryId].valueSelected
    }
    
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, decimal: Double) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].valueDecimal != decimal {
            item[entryId].valueDecimal = decimal
            save(updated: item, message: String(localized: "Update decimal", bundle: .module).localizedString)
        }
    }
    
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, number: Int) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].valueNumber != number {
            item[entryId].valueNumber = number
            save(updated: item, message: String(localized: "Update number", bundle: .module).localizedString)
        }
    }
    
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, selected: Bool) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].valueSelected != selected {
            item[entryId].toggleSelection()
            save(updated: item, message: String(localized: "Update Selection", bundle: .module).localizedString)
        }
    }
    
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, value: String) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].value != value {
            item[entryId].value = value
            save(updated: item, message: String(localized: "Update value", bundle: .module).localizedString)
        }
    }
}

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: .text, value: content)
    }

    @MainActor func merge(itemId: UUID, entries: [ValueEntryModel], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
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
            if !linkRegisterController.used(for: itemRowModel).isEmpty {
                effectedLinks = false
                break;
            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(updated: item, message: String(localized: "Entries replaced", bundle: .module).localizedString)
            return []
        }
        return itemRowModels
    }
}

// MARK: - GameController

extension EditController {
    @MainActor func add(model childModel: ValueModel, into itemId: UUID?) {
        guard let itemId else { return }
        let entry = ValueEntryModel(id: UUID(), name: "", type: .text, value: "", valueId: childModel.id)
        add(entry: entry, into: itemId)
    }
}

