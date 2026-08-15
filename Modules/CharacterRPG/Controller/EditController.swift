// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import os.log
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
    public let isMove: Bool

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .characterLink)
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .tableLink)
    }
}

struct EditController: Sendable {
    @MainActor init(root: CharacterRootModel, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.root = root

        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.valueEditModel = ValueEditModel()
    }

    let root: CharacterRootModel

    let itemController: ItemController
    let tagController: TagController

    let editorModel: ItemEditorModel
    let valueEditModel: ValueEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = ValueModel

    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

    var canAddGroups: Bool { true }
}

extension EditController: SheetEditTypeControllable {
    var supportedSheetEditTypes: [SheetModelEditType] {
        [.text, .number, .decimal, .selection]
    }

    @MainActor
    func updateSheetEditType(itemId: UUID, entryId: UUID, editType: SheetModelEditType) {
        guard let item = editModel(for: itemId) else { return }
        let valueType: ValueEntryModel.ValueType
        switch editType {
        case .text:
            valueType = .text
        case .number:
            valueType = .number
        case .decimal:
            valueType = .decimal
        case .selection:
            valueType = .selection
        case .none:
            return
        }
        guard item[entryId].type != valueType else { return }
        item[entryId].type = valueType
        save(updated: item, message: String(localized: "Change Value Type", bundle: .module).localizedString)
    }
}

extension EditController {
    @MainActor
    public func gameValueEntryUpdate(
        itemId: UUID,
        entryId: UUID?
    ) -> NetworkCodableDataType? {
        guard let entryId,
              let character = itemController.itemSync(for: itemId),
              let entry = character.entries.first(where: { $0.id == entryId }),
              let data = GameValueEntryUpdate(
                  characterId: itemId,
                  entryId: entry.id,
                  name: entry.name,
                  typeRawValue: entry.type.rawValue,
                  isGenerator: entry.isGenerator,
                  value: entry.value,
                  displayState: entry.displayState
              ).encodeData() else {
            return nil
        }
        return NetworkCodableDataType(
            id: itemId,
            type: .value,
            version: 1,
            data: data
        )
    }
}
 
// MARK: - EntryList editor

extension EditController {
    public var linkModules: [NetworkModules] { [.value, .dice, .pdf, .table] }
    
    public var additioanlEnrtryViewType: AdditionalEntryViewType { .inline }
    
    @MainActor public func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessable, textModel: LinkHighlightTextModel?) -> AnyView {
        AnyView(AddtionalEntryRow(source: source, entry: entry, textModel: textModel).equatable())
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
        MasterRPGTips.recordContentLinked()
    }

    /// Unlinks an entry's dice, mirroring the `.dice` case of `add(link:...)`.
    /// The entry's value type is left as-is — only the link itself is removed.
    @MainActor public func removeDice(itemId: UUID, entryId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        var entry = item[entryId]
        guard entry.diceId != nil else { return }
        entry.diceId = nil
        item[entryId] = entry
        save(updated: item, message: String(localized: "Remove Dice", bundle: .module).localizedString)
    }

    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        (module == .value && entryId != nil) || module == .dice || module == .pdf || (module == .table && entryId != nil)
    }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        CharacterEditorRoute.linkSelection(itemRowModel)
    }
    
    @MainActor public func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String {
        guard let item = editModel(for: itemId), let entry = entry as? ValueEntryModel else { return "" }
        return root.linkController.linkText(model: item, entry: entry)
    }
    
    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return [] }
        return item.entries.compactMap {
            guard $0.id != sourceEntryId, let valueId = $0.valueId else { return nil }
            return FolderRepresentable(id: valueId, name: $0.name)
        }
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return nil }
        let resolvedParentId = item.groupId ?? item.parentId
        guard let resolvedParentId, let parent = itemControllable.itemSync(for: resolvedParentId) as? Model else { return nil }
        return FolderRepresentable(id: parent.id, name: parent.name)
    }

    /// Whether `parentFolder(itemId:)` resolved via the value-group hierarchy
    /// (`groupId` — e.g. an entry inside a "Skills" sub-group, whose owning
    /// character it can legitimately move back out to) as opposed to falling
    /// back to the unrelated item-list folder hierarchy (`parentId`). A value
    /// entry has nowhere valid to "move out" to when the only resolvable
    /// parent is a folder — see `SheetContextMenuView.moveOutOfGroupButton`.
    @MainActor func isValueGroupParent(itemId: UUID) -> Bool {
        (itemControllable.itemSync(for: itemId) as? Model)?.groupId != nil
    }
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        CharacterEditorRoute.quickEditor(itemRowModel.itemId)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessable) async {
        let originalParentId = itemController.itemSync(for: item.id)?.parentId
        let copyId = await duplicate(itemId: item.id, withCopy: true)

        // For folders: rebuild entries with independent child copies (duplicate() produces stale entry IDs)
        if item.isFolder, let copyFolder = editModel(for: copyId),
           let originalFolder = editModel(for: item.id) {
            var newEntries: [Model.Entry] = []
            for entry in originalFolder.entries {
                let childCopyId = await duplicate(itemId: entry.childId, withCopy: false)
                if let childCopy = editModel(for: childCopyId) {
                    childCopy.parentId = copyId
                    save(updated: childCopy, message: String(localized: "Duplicate child", bundle: .module).localizedString)
                }
                newEntries.append(Model.Entry.newChild(id: childCopyId))
            }
            copyFolder.entries = newEntries
            save(updated: copyFolder, message: String(localized: "Duplicate folder", bundle: .module).localizedString)
        }

        // For collections: ValueModel.duplicate() creates new entry IDs (childId = id), losing the
        // member references. Replace the broken entries in one shot with correct newChild entries.
        if !item.isFolder, item.category == itemControllable.collectionCategory,
           let originalCollection = editModel(for: item.id),
           let copyCollection = editModel(for: copyId) {
            copyCollection.entries = originalCollection.entries.map { Model.Entry.newChild(id: $0.childId) }
            save(updated: copyCollection, message: String(localized: "Fix collection entries", bundle: .module).localizedString)
        }

        // Re-register the duplicate in the same parent folder
        if let parentId = originalParentId {
            addItem(itemId: copyId, parentId: parentId)
        }

        // Add the duplicate as a new reference in every collection that contains the original.
        // Skip when duplicating a collection itself (collections cannot be members of other collections).
        if !item.isFolder, item.category != itemControllable.collectionCategory {
            let originalId = item.id
            for containerId in itemControllable.itemDataModel.items {
                guard let container = itemControllable.itemSync(for: containerId),
                      container.category == itemControllable.collectionCategory,
                      container.entries.contains(where: { $0.childId == originalId }) else { continue }
                addGroup(itemId: containerId, childId: copyId)
            }
        }
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
                duplicates.first(where: { $0.id == copyId })?.groupId = copyItem.id
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

    @MainActor func isOrphanedHidden(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? ValueModel else { return false }
        guard item.displayState == 1 && item.parentId == nil else { return false }
        if let groupId = item.groupId {
            // Hidden with a groupId: orphaned if the parent is gone or deleted
            let parent = itemControllable.itemSync(for: groupId)
            return parent == nil || parent?.displayState == 2
        }
        return true  // no parentId, no groupId → Phase 1 orphan
    }

    @MainActor func willRepairOrphan(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.groupId != nil else { return }
        item.groupId = nil
        save(updated: item, message: String(localized: "Repair orphan", bundle: .module).localizedString)
    }

    @MainActor func willRestore(item: inout ValueModel) {
        if let groupId = item.groupId {
            // Clear groupId if parent is deleted OR doesn't exist
            if let groupItem = editModel(for: groupId) {
                if groupItem.displayState == 2 {
                    item.groupId = nil
                }
            } else {
                // Parent doesn't exist - clear the orphaned groupId
                item.groupId = nil
            }
        }
    }

    @MainActor func willDeleteChildren(of item: ValueModel) async {
        guard item.category != .folder else { return }
        for entry in item.entries {
            guard let valueId = entry.valueId else { continue }
            await Task.yield()
            await delete(itemId: valueId)
        }
    }

    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        let groupId = await itemController.addNew(type: .item)
        reset(hidden: true, itemId: groupId)
        guard let group = editModel(for: groupId) else { return groupId }
        group.groupId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.valueId = groupId
        add(entry: entry, itemId: itemId)
        return entry.id
    }
    
    @MainActor func addItemAsGroup(itemId: UUID, groupId: UUID, forceSave: Bool = false) async -> UUID {
        reset(hidden: true, itemId: groupId, forceSave: forceSave)
        guard let group = editModel(for: groupId) else { return groupId }
        group.groupId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString, forceSave: forceSave)
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.valueId = groupId
        add(entry: entry, itemId: itemId, forceSave: forceSave)
        return entry.id
    }


    @MainActor func canBecomeGroup(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? ValueModel else { return false }
        return item.groupId == nil
    }

    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?) async -> UUID {
        guard let item = editModel(for: itemId), let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return UUID() }

        let groupId: UUID
        if let existingItemId, let existingGroup = editModel(for: existingItemId) {
            groupId = existingItemId
            existingGroup.groupId = itemId
            existingGroup.isGroupHiddenToggle = true
            save(updated: existingGroup, message: String(localized: "prepare group", bundle: .module).localizedString)
            item.entries[index].name = existingGroup.name
            item.entries[index].value = existingGroup.description
        } else {
            groupId = await itemController.addNew(type: .item)
            reset(hidden: true, itemId: groupId)
            guard let group = editModel(for: groupId) else { return groupId }
            group.name = item.entries[index].name.withoutLink()
            group.description = item.entries[index].value
            group.groupId = itemId
            save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        }
        item.entries[index].valueId = groupId
        save(updated: item, message: String(localized: "Convert to group", bundle: .module).localizedString)
        return groupId
    }
    
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        let old = item[entryId].type
        let newType = termineType(content: content, currentType: old)
        if old != newType {
            item[entryId].type = newType
            save(updated: item, message: String(localized: "update value type", bundle: .module).localizedString, forceSave: forceSave)
        }
        updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: true, forceSave: forceSave)
        guard let valueId = item[entryId].valueId else { return }
        let fixedName = name.withoutLink()
        reset(name: fixedName, itemId: valueId, forceSave: forceSave)
        reset(description: content, itemId: valueId, forceSave: forceSave)
    }

    private func parseDouble(from string: String) -> Double? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // `Double(_:format:)`/`Int(_:format:)` do prefix matching (e.g. "3.5" parses as
        // the Int 3, silently dropping ".5"), unlike the strict, allowsFloats-respecting
        // NumberFormatter this replaced. `wholeMatch(of:)` requires the entire string to
        // match, restoring that behavior.
        return trimmed.wholeMatch(of: FloatingPointFormatStyle<Double>(locale: Locale.current))?.output
    }

    private func parseInteger(from string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // `IntegerFormatStyle`'s `wholeMatch` alone still accepts "3.5" (parsing the
        // integer prefix "3" and treating the match as complete), so explicitly reject
        // any decimal separator to keep the old `allowsFloats = false` semantics.
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        guard !trimmed.contains(decimalSeparator) else { return nil }
        return trimmed.wholeMatch(of: IntegerFormatStyle<Int>(locale: Locale.current))?.output
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
            saveGameDataToPermanent(itemId: itemId, entryId: entryId)
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, number: Int) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].valueNumber != number {
            item[entryId].valueNumber = number
            save(updated: item, message: String(localized: "Update number", bundle: .module).localizedString)
            saveGameDataToPermanent(itemId: itemId, entryId: entryId)
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, selected: Bool) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].valueSelected != selected {
            item[entryId].toggleSelection()
            save(updated: item, message: String(localized: "Update Selection", bundle: .module).localizedString)
            saveGameDataToPermanent(itemId: itemId, entryId: entryId)
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, value: String) {
        guard let entryId, let item = editModel(for: itemId) else { return }
        if item[entryId].value != value {
            item[entryId].value = value
            save(updated: item, message: String(localized: "Update value", bundle: .module).localizedString)
            saveGameDataToPermanent(itemId: itemId, entryId: entryId)
        }
    }

    // MARK: - Save Game Changes to Permanent Storage

    /// Saves the current game data entry to the permanent (non-game) storage
    /// This is used by the inline editor to persist player changes made during gameplay
    @MainActor private func saveGameDataToPermanent(itemId: UUID, entryId: UUID) {
        // Only save to permanent if we're in game mode
        guard itemController.itemDataModel.isGameMode else { return }

        // Get the current game item
        guard let gameItem = itemController.itemSync(for: itemId, noGame: false) else { return }

        // Get the permanent item (or create copy from game item if doesn't exist)
        guard let permanentItem = itemController.itemSync(for: itemId, noGame: true)?.copy() as? ValueModel else { return }

        // Copy the specific entry from game to permanent
        let gameEntry = gameItem[entryId]
        permanentItem[entryId] = gameEntry

        // Save to permanent storage with forceSave flag
        itemController.replace(model: permanentItem, isInsert: false, forceSave: true)
    }
}

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: termineType(content: content, currentType: .text), value: content)
    }

    private func termineType(content: String, currentType: ValueEntryModel.ValueType) -> ValueEntryModel.ValueType {
        guard currentType == .text else { return currentType }
        guard content.allSatisfy({
            $0 == " " || $0 == "+" || $0 == "-" || $0 == "*" || $0 == "/" || $0 == "." || $0 == "," || $0.isNumber
        }) else { return currentType }
        if parseInteger(from: content) == nil && (parseDouble(from: content) != nil || content.contains("/")) {
            return .decimal
        }
        return .number
    }
    
    @MainActor func merge(itemId: UUID, entries: [ValueEntryModel]) -> [ValueEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        return entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.value = entry.value
            return foundEntry ?? entry
        }
    }

    @MainActor func merge(itemId: UUID, entries: [ValueEntryModel], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var newEntries = merge(itemId: itemId, entries: entries)
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
            save(updated: item, message: String(localized: "Entries replaced", bundle: .module).localizedString, forceSave: forceSave)
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

// MARK: - EditControllable

extension EditController {
    /// Creates a new character value from a sheet built elsewhere (e.g. a
    /// generated table outcome, see `TableGenerationController`/
    /// `SimpleSheetEditingSession` in TableRPG/CoreRPG). `sheet` is a
    /// wrapping root whose own name is never user-editable — its one entry
    /// stands in as that editable "root" instead, and links to a nested
    /// sheet (that entry's own `entries.first`) holding the actual result
    /// entries: the wrapping entry's name/content become the new value's
    /// name/description, and the nested sheet's entries become the new
    /// value's own entries.
    @MainActor func addItem(sheet: SheetModel, forceSave: Bool) async -> UUID? {
        guard let wrapper = sheet.entries.first else { return nil }
        let itemId = await itemController.addNew(type: .item)
        guard let item = editModel(for: itemId) else { return nil }
        item.name = wrapper.name
        item.description = wrapper.description
        save(
            updated: item,
            message: String(localized: "Add from Generator", bundle: .module).localizedString,
            forceSave: forceSave
        )
        for entry in wrapper.entries.first?.entries ?? [] {
            _ = insertEntry(itemId: itemId, name: entry.name, content: entry.description, position: .end, forceSave: forceSave)
        }
        return itemId
    }
}

// MARK: - Final Repair

extension EditController {
    @MainActor func repairCharacterContrains() {
        let itemIds = itemControllable.itemDataModel.items

        // Build: groupItemId → [ownerIds that reference it via entry.valueId]
        // editModel returns ValueModel, giving typed access to ValueEntryModel.valueId
        var valueIdOwners: [UUID: [UUID]] = [:]
        for itemId in itemIds {
            guard let item = editModel(for: itemId), item.displayState != 2 else { continue }
            for entry in item.entries {
                guard let valueId = entry.valueId else { continue }
                valueIdOwners[valueId, default: []].append(itemId)
            }
        }

        for itemId in itemIds {
            guard let item = itemControllable.itemSync(for: itemId) as? ValueModel,
                  item.displayState != 2 else { continue }

            if item.isFolder && item.groupId == nil {
                repairFolderConstraints(itemId: itemId)
            } else if item.category == itemControllable.collectionCategory && item.displayState == 0 && item.groupId == nil {
                repairCollectionConstraints(itemId: itemId)
            } else if item.displayState == 1 {
                repairGroupItemConstraints(itemId: itemId, valueIdOwners: valueIdOwners)
            } else if item.displayState == 0 && item.groupId == nil && !item.specialCategory {
                repairCharacterItemConstraints(itemId: itemId)
            }
        }
    }

    @MainActor private func repairFolderConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let before = item.entries.map(\.childId)

        let removedNames = before.compactMap { childId -> String? in
            guard let child = itemControllable.itemSync(for: childId) else { return nil }
            let badParent = child.parentId != itemId
            let isNestedFolder = child.isFolder
            let isHidden = child.displayState != 0
            guard badParent || isNestedFolder || isHidden else { return nil }
            return child.name
        }

        item.entries = item.entries.filter { entry in
            guard let child = itemControllable.itemSync(for: entry.childId),
                  child.displayState == 0,
                  child.parentId == itemId,
                  !child.isFolder
            else { return false }
            return true
        }
        item.entries.sort {
            let n1 = itemControllable.nameSync(itemId: $0.childId)
            let n2 = itemControllable.nameSync(itemId: $1.childId)
            return n1.localizedCompare(n2) == .orderedAscending
        }
        guard item.entries.map(\.childId) != before else { return }

        let afterNames = item.entries.map { itemControllable.nameSync(itemId: $0.childId) }
        if !removedNames.isEmpty {
            Logger.editController.warning("[Repair] Folder '\(item.name, privacy: .public)': removed invalid children \(removedNames, privacy: .public)")
        }
        Logger.editController.info("[Repair] Folder '\(item.name, privacy: .public)': entries now \(afterNames, privacy: .public)")

        save(updated: item, message: String(localized: "Repair folder", bundle: .module).localizedString)
    }

    @MainActor private func repairCollectionConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        let before = item.entries.count

        let removedNames: [String] = item.entries.compactMap { entry in
            guard let child = itemControllable.itemSync(for: entry.childId) as? ValueModel else {
                return "<missing \(entry.childId)>"
            }
            let invalid = child.displayState != 0 || child.groupId != nil || child.specialCategory
            return invalid ? child.name : nil
        }

        item.entries = item.entries.filter { entry in
            guard let child = itemControllable.itemSync(for: entry.childId) as? ValueModel,
                  child.displayState == 0,
                  child.groupId == nil,
                  !child.specialCategory
            else { return false }
            return true
        }
        guard item.entries.count != before else { return }

        Logger.editController.warning("[Repair] Collection '\(item.name, privacy: .public)': removed \(before - item.entries.count) invalid children \(removedNames, privacy: .public)")

        save(updated: item, message: String(localized: "Repair collection", bundle: .module).localizedString)
    }

    @MainActor private func repairCharacterItemConstraints(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        var changed = false

        // Repair 1: orphaned parentId — item not present in the folder's entries
        if let parentId = item.parentId {
            let isInFolder = itemControllable.itemSync(for: parentId).map { parent in
                parent.displayState != 2 && parent.isFolder && parent.entries.contains { $0.childId == itemId }
            } ?? false
            if !isInFolder {
                let parentName = itemControllable.nameSync(itemId: parentId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .public)': cleared orphaned parentId (folder '\(parentName, privacy: .public)' has no matching entry)")
                item.parentId = nil
                changed = true
            }
        }

        // Repair 2: entry.valueId must only point to GroupItems (displayState == 1)
        var entriesChanged = false
        let cleanedEntries: [ValueEntryModel] = item.entries.map { entry in
            guard let valueId = entry.valueId else { return entry }
            guard let target = itemControllable.itemSync(for: valueId) as? ValueModel else {
                let targetName = itemControllable.nameSync(itemId: valueId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .public)': entry '\(entry.name, privacy: .public)' had non-GroupItem valueId pointing to '\(targetName, privacy: .public)' — cleared")
                entriesChanged = true
                return ValueEntryModel(
                    id: entry.id, name: entry.name, type: entry.type,
                    isGenerator: entry.isGenerator, value: entry.value,
                    diceId: entry.diceId, valueId: nil, displayState: entry.displayState
                )
            }
            guard target.displayState == 1 else {
                if target.groupId == itemId, let groupItem = editModel(for: valueId) {
                    groupItem.parentId = nil
                    groupItem.displayState = 1
                    save(updated: groupItem, message: String(localized: "Repair group item", bundle: .module).localizedString)
                    return entry
                }

                let targetName = itemControllable.nameSync(itemId: valueId)
                Logger.editController.warning("[Repair] Character '\(item.name, privacy: .public)': entry '\(entry.name, privacy: .public)' had non-GroupItem valueId pointing to '\(targetName, privacy: .public)' — cleared")
                entriesChanged = true
                return ValueEntryModel(
                    id: entry.id, name: entry.name, type: entry.type,
                    isGenerator: entry.isGenerator, value: entry.value,
                    diceId: entry.diceId, valueId: nil, displayState: entry.displayState
                )
            }
            return entry
        }
        if entriesChanged {
            item.entries = cleanedEntries
            changed = true
        }

        if changed {
            save(updated: item, message: String(localized: "Repair character item", bundle: .module).localizedString)
        }
    }

    @MainActor private func repairGroupItemConstraints(itemId: UUID, valueIdOwners: [UUID: [UUID]]) {
        guard let groupItem = editModel(for: itemId) else { return }
        groupItem.parentId = nil // groups always on root level / no relationship to folders

        let owners = valueIdOwners[itemId]
        let firstOwnerId = owners?.first
        if groupItem.groupId != firstOwnerId {
            if let oldOwnerId = groupItem.groupId {
                removeOld(groupItemId: itemId, valueId: oldOwnerId)
            }
            groupItem.groupId = firstOwnerId
        }
        if groupItem.groupId == nil {
            groupItem.displayState = 0 // make this visible (or should I remove it?
        }
        save(
            updated: groupItem,
            message: String(localized: "Repairing group item", bundle: .module).localizedString
        )
        guard let owners, owners.count > 1 else { return }
        for ownerId in owners.dropFirst() {
            removeOld(groupItemId: itemId, valueId: ownerId)
        }
    }
    
    @MainActor private func removeOld(groupItemId: UUID, valueId: UUID) {
        guard let oldOwner = editModel(for: valueId) else { return }
        oldOwner.entries = oldOwner.entries.map {
            if $0.valueId == groupItemId {
                var changed = $0
                changed.valueId = nil
                return changed
            } else {
                return $0
            }
        }
        let groupItemName = itemControllable.nameSync(itemId: groupItemId)

        Logger.editController.warning("[Repair] GroupItem '\(groupItemName, privacy: .public)': removed duplicate reference from '\(oldOwner.name, privacy: .public)'")
        save(updated: oldOwner, message: String(localized: "Repair group item", bundle: .module).localizedString)
    }
}
