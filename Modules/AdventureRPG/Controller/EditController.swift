// @copyright André Trettin

import CoreRPG
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif
import Observation
import RegexBuilder
import SwiftUI
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

@MainActor @Observable
final class AdventureEditModel: Sendable {
    let selectionAudio: ItemSelectionModel = ItemSelectionModel()
    let selectionCharacter: ItemSelectionModel = ItemSelectionModel()
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionMap: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
    let selectionSpace: ItemSelectionModel = ItemSelectionModel()
    let selectionTable: ItemSelectionModel = ItemSelectionModel()
    let selectionWeather: ItemSelectionModel = ItemSelectionModel()
}

struct LinkAdventureModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let isMove: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .adventureLink)
        CodableRepresentation(contentType: .audioLink)
        CodableRepresentation(contentType: .characterLink)
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .mapLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .photoLink)
        CodableRepresentation(contentType: .ruleLink)
        CodableRepresentation(contentType: .spaceLink)
        AdventureSupplementalLinkRepresentations()
    }
}

private struct AdventureSupplementalLinkRepresentations: TransferRepresentation {
    typealias Item = LinkAdventureModuleTransferable

    var body: some TransferRepresentation {
        CodableRepresentation(contentType: .tableLink)
        CodableRepresentation(contentType: .weatherLink)
    }
}

struct EditController: Sendable {
    @MainActor init(root: AdventureRootModel, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.root = root
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.adventureEditModel = AdventureEditModel()
    }

    let root: AdventureRootModel

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let adventureEditModel: AdventureEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = AdventureModel

    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }

    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }

    var canAddGroups: Bool { true }
    var canConvertGroups: Bool { true }
}
    
// MARK: - EntryList editor

extension EditController {
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        true
    }

    @MainActor public func update(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        if let adventureId = item[entryId].adventureId {
            reset(name: name, itemId: adventureId, forceSave: forceSave)
            reset(description: content, itemId: adventureId, forceSave: forceSave)
        } else {
            updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: false, forceSave: forceSave)
        }
    }

    public var linkModules: [NetworkModules] { [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .rule, .space, .table, .weather] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        AdventureEditorRoute.linkSelection(itemRowModel)
    }
}

// MARK: - Group Management

extension EditController {
    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        let groupId = await itemController.addNew(type: .item)
        reset(hidden: true, itemId: groupId)
        guard let group = editModel(for: groupId) else { return groupId }
        group.groupId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.adventureId = groupId
        add(entry: entry, itemId: itemId)
        return entry.id
    }

    @MainActor func canBecomeGroup(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? AdventureModel else { return false }
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
            item.entries[index].content = existingGroup.description
        } else {
            groupId = await itemController.addNew(type: .item)
            reset(hidden: true, itemId: groupId)
            guard let group = editModel(for: groupId) else { return groupId }
            group.name = item.entries[index].name.withoutLink()
            group.description = item.entries[index].content
            group.groupId = itemId
            save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        }
        item.entries[index].adventureId = groupId
        save(updated: item, message: String(localized: "Convert to group", bundle: .module).localizedString)
        return groupId
    }

    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return [] }
        return item.entries.compactMap {
            guard $0.id != sourceEntryId, let adventureId = $0.adventureId else { return nil }
            return FolderRepresentable(id: adventureId, name: $0.name)
        }
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return nil }
        let resolvedParentId = item.groupId ?? item.parentId
        guard let resolvedParentId, let parent = itemControllable.itemSync(for: resolvedParentId) as? Model else { return nil }
        return FolderRepresentable(id: parent.id, name: parent.name)
    }

    @MainActor func isOrphanedHidden(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? AdventureModel else { return false }
        guard item.displayState == 1 && item.parentId == nil else { return false }
        if let groupId = item.groupId {
            let parent = itemControllable.itemSync(for: groupId)
            return parent == nil || parent?.displayState == 2
        }
        return true
    }

    @MainActor func willRepairOrphan(itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard item.groupId != nil else { return }
        item.groupId = nil
        save(updated: item, message: String(localized: "Repair orphan", bundle: .module).localizedString)
    }

    @MainActor func willRestore(item: inout AdventureModel) {
        if let groupId = item.groupId {
            if let groupItem = editModel(for: groupId) {
                if groupItem.displayState == 2 {
                    item.groupId = nil
                }
            } else {
                item.groupId = nil
            }
        }
    }

    @MainActor func willDeleteChildren(of item: AdventureModel) async {
        guard item.category != .folder else { return }
        for entry in item.entries {
            guard let adventureId = entry.adventureId else { continue }
            await Task.yield()
            await delete(itemId: adventureId)
        }
    }
}

// MARK: - Duplicate with sub-groups

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessable) async {
        guard let model = editModel(for: item.id) else { return }
        let originalParentId = model.parentId
        let (copies, copyId) = duplicateSubAdventure(model: model, withCopy: true)
        for copy in copies {
            itemControllable.replace(model: copy, isInsert: true)
        }
        if let parentId = originalParentId {
            addItem(itemId: copyId, parentId: parentId)
        }
        let originalId = item.id
        for containerId in itemControllable.itemDataModel.items {
            guard let container = itemControllable.itemSync(for: containerId),
                  container.category == itemControllable.collectionCategory,
                  container.entries.contains(where: { $0.childId == originalId }) else { continue }
            addGroup(itemId: containerId, childId: copyId)
        }
    }

    @MainActor private func duplicateSubAdventure(model: AdventureModel, withCopy: Bool) -> ([AdventureModel], UUID) {
        let copyItem = withCopy ? model.duplicate() : model.duplicateWithoutCopy()
        var copies: [AdventureModel] = [copyItem]
        var newEntries: [AdventureEntryModel] = []
        for entry in model.entries {
            var duplicatedEntry = entry.duplicate()
            if let adventureId = entry.adventureId,
               let childModel = itemControllable.itemSync(for: adventureId) as? AdventureModel {
                let (childCopies, childCopyId) = duplicateSubAdventure(model: childModel, withCopy: false)
                childCopies.first?.groupId = copyItem.id
                copies.append(contentsOf: childCopies)
                duplicatedEntry.adventureId = childCopyId
            }
            newEntries.append(duplicatedEntry)
        }
        copyItem.entries = newEntries
        return (copies, copyItem.id)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(diceId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.diceId = diceId
        save(updated: item, message: String(localized: "Change Dice", bundle: .module).localizedString)
    }

    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Changed Photo", bundle: .module).localizedString)
    }
}

// MARK: - Quick Link Editor

extension EditController {
    func create(name: String, content: String) -> AdventureEntryModel {
        AdventureEntryModel(id: UUID(), name: name, content: content)
    }

    @MainActor func merge(itemId: UUID, entries: [AdventureEntryModel]) -> [AdventureEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        return entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
    }

    @MainActor
    func merge(itemId: UUID, entries: [AdventureEntryModel], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = root.itemController.config.module
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
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        AdventureEditorRoute.quickEditor(itemRowModel.itemId)
    }
}

// MARK: - AI Extraction

#if !os(tvOS)
extension EditController {
    @MainActor func applyExtractedContent(_ content: TableSummaryAnalysis, to itemId: UUID, selection: TextSummaryPropertySelection) {
        if selection.applyTitle {
            reset(name: content.title, itemId: itemId)
        }
        if selection.applyDescription {
            reset(description: content.description, itemId: itemId)
        }
        if selection.applyTags {
            reset(tags: content.tags, itemId: itemId)
        }
    }
}
#endif

extension EditController {

    @MainActor func collectPhotos(itemId: UUID, entryId: UUID) {
        let photoIds = root.linkController.collectLinks(of: .photo, from: itemId)
        let links = photoIds.map {
            root.photoRoot.linkControllable.generateLink(itemId: $0)
        }.sorted()
        update(itemId: itemId, entryId: entryId, name: "Collection", content: links.joined(separator: "\n"))
    }
}
