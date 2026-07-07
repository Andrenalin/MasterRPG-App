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
        CodableRepresentation(contentType: .spaceLink)
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
        let sheetRootModel = SheetRootModel(
            rootManager: root.rootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: sheetEditorModel
        )
        editorModel.sheetRootModel = sheetRootModel
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
}
    
// MARK: - EntryList editor

extension EditController {
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        true
    }

    public var linkModules: [NetworkModules] { [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        AdventureEditorRoute.linkSelection(itemRowModel)
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
    func merge(itemId: UUID, entries: [AdventureEntryModel], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
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
            save(updated: item, message: String(localized: "Entries replaced", bundle: .module).localizedString)
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
