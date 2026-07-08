// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class TableEditModel: Sendable {
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
}

struct LinkTableModuleTransferable: LinkDataTransferable {
    public var module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String
    public let isMove: Bool

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .tableLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

struct EditController: Sendable {
    @MainActor init(diceRoot: DiceRootModel, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.diceRoot = diceRoot

        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.tableEditModel = TableEditModel()
    }

    let diceRoot: DiceRootModel
    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let tableEditModel: TableEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = TableModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }
}
    
// MARK: - EntryList editor

extension EditController {
    public var linkModules: [NetworkModules] { [.dice, .pdf, .table] }
    
    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        module == .table || module == .dice || module == .pdf
    }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        TableEditorRoute.linkSelection(itemRowModel)
    }
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        TableEditorRoute.quickEditor(itemRowModel.itemId)
    }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(diceId: UUID?, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.diceId = diceId
        save(updated: editModel, message: String(localized: "Added Dice", bundle: .module).localizedString)
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

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> TableEntryModel {
        TableEntryModel(id: UUID(), name: name, content: content)
    }

    @MainActor func merge(itemId: UUID, entries: [TableEntryModel]) -> [TableEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        return entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
            return foundEntry ?? entry
        }
    }

    @MainActor func merge(itemId: UUID, entries: [TableEntryModel], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var newEntries = entries.map { entry in
            var foundEntry = item.entries.first(where: { $0.name == entry.name })
            foundEntry?.content = entry.content
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
