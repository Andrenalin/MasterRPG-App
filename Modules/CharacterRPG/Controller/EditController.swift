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

    var canAddGroups: Bool { true }
}

extension EditController: SheetEditTypeControllable {
    var supportedSheetEditTypes: [SheetModelEditType] {
        [.text, .number, .decimal, .selection]
    }

    @MainActor
    func updateSheetEditType(itemId: UUID, entryId: UUID, editType: SheetModelEditType) {
        guard let item = editModel(for: itemId), let valueType = ValueEntryModel.ValueType(editType: editType) else { return }
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
              let entry = character.entries.first(where: { $0.id == entryId })
        else { return nil }

        // `itemId` is whichever item the row is currently displayed under —
        // for a nested value "group" table that's the group, not the root
        // Character. Walk up via groupId so the wire message always names
        // the root (what the receiver's sender guard checks against) plus a
        // path the receiver can replay to find the same nested entry.
        // See CODE_AUDIT_Game §5.3.
        guard let leafIndex = character.entries.firstIndex(where: { $0.id == entryId }) else {
            return nil
        }
        var indices = [leafIndex]
        var currentItem = character
        var currentItemId = itemId
        var depth = 0
        while let ownerId = currentItem.groupId {
            guard depth < RecursionLimits.maxValueLinkDepth,
                  let owner = itemController.itemSync(for: ownerId),
                  let linkIndex = owner.entries.firstIndex(where: { $0.valueId == currentItemId })
            else { return nil }
            indices.append(linkIndex)
            currentItem = owner
            currentItemId = ownerId
            depth += 1
        }
        let rootCharacterId = currentItemId
        let path = indices.count > 1 ? Array(indices.reversed()) : nil

        guard let data = GameValueEntryUpdate(
                  characterId: rootCharacterId,
                  entryId: entry.id,
                  name: entry.name,
                  typeRawValue: entry.type.rawValue,
                  isGenerator: entry.isGenerator,
                  value: entry.value,
                  displayState: entry.displayState,
                  path: path
              ).encodeData() else {
            return nil
        }
        return NetworkCodableDataType(
            id: rootCharacterId,
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
        AnyView(AdditionalEntryRow(source: source, entry: entry, textModel: textModel).equatable())
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
            if entry.type != .number && entry.type != .decimal {
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
            if entry.type != .number && entry.type != .decimal {
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

// MARK: - Grouping & Entry Type Helpers

extension EditController {
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
    }
    
    @MainActor func removePhotos(itemId: UUID) async {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = nil
        item.photos.removeAll()
        save(updated: item, message: String(localized: "remove photos", bundle: .module).localizedString)
    }

    // `isOrphanedHidden`/`willRepairOrphan`/`willRestore` use `EditControllable`'s
    // shared `GroupableModel`-constrained default now that `ValueModel` conforms to
    // `GroupableModel` — see CODE_AUDIT_EditItem §9.5.

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

    /// Internal (not `private`): shared with `create(name:content:)` in
    /// `EditController+InlineEditor.swift`. See CODE_AUDIT_Character §9.7.
    func termineType(content: String, currentType: ValueEntryModel.ValueType) -> ValueEntryModel.ValueType {
        guard currentType == .text else { return currentType }
        guard content.allSatisfy({
            $0 == " " || $0 == "+" || $0 == "-" || $0 == "*" || $0 == "/" || $0 == "." || $0 == "," || $0.isNumber
        }) else { return currentType }
        if parseInteger(from: content) == nil && (parseDouble(from: content) != nil || content.contains("/")) {
            return .decimal
        }
        return .number
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

