// @copyright André Trettin

import CoreRPG
import Foundation
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
    @MainActor init(root: AdventureRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, tagController: TagController) {
        self.root = root
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        self.tagController = tagController
        
        self.editorModel = ItemEditorModel()
        self.adventureEditModel = AdventureEditModel()
    }

    let root: AdventureRootModel

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
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
}
    
// MARK: - EntryList editor

extension EditController {
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        true
    }

    public var linkModules: [NetworkModules] { [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        EditorRoute.linkSelection(itemRowModel)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Changed Photo").localizedString)
    }
}

// MARK: - Quick Link Editor

extension EditController {
    func create(name: String, content: String) -> AdventureEntryModel {
        AdventureEntryModel(id: UUID(), name: name, content: content)
    }

    @MainActor
    func merge(itemId: UUID, entries: [AdventureEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
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
            if !linkRegisterControllable.used(for: itemRowModel).isEmpty {
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
    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [AdventureEntryModel] {
        guard let anotherIds else {
            let otherEntries: [LinkEntryModel]
            switch module {
            case .dice:
                otherEntries = root.diceRoot.linkController.link(for: .table)
            case .map:
                otherEntries = root.mapRoot.linkController.link(for: .adventure)
            case .table:
                otherEntries = root.tableRoot.linkController.link(for: .adventure)
            case .value:
                otherEntries = root.characterRoot.linkController.link(for: .adventure)
            default:
                otherEntries = root.linkController.link(for: .adventure)
            }
            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
        }
        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
            switch module {
            case .adventure:
                return root.linkController.linkEntries(for: anotherId)
            case .dice:
                return root.diceRoot.linkController.linkEntries(for: anotherId)
            case .map:
                return root.mapRoot.linkController.linkEntries(for: anotherId)
            case .table:
                return root.tableRoot.linkController.linkEntries(for: anotherId)
            case .value:
                return root.characterRoot.linkController.linkEntries(for: anotherId)
            default:
                return []
            }
        }
        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
    }

    @MainActor
    func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [AdventureEntryModel] {
        guard let entries = root.itemController.itemSync(for: itemId)?.entries else { return [] }
        return entries.map { entry in
            var replacedEntry = entry
            linkEntries.forEach { linkEntry in
                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.content }, setLink: { var result = $1; result.content = $0; return result }, caseInsensitive: caseInsensitive, words: words)
            }
            return replacedEntry
        }
    }
}

extension EditController {
    
    @MainActor func collectPhotos(itemId: UUID, entryId: UUID) {
        let photoIds = root.linkController.collectLinks(of: .photo, from: itemId)
        let links = photoIds.map {
            root.photoRoot.linkController.generateLink(itemId: $0)
        }.sorted()
        update(itemId: itemId, entryId: entryId, name: "Collection", content: links.joined(separator: "\n"))
    }
}
