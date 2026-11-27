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
    @MainActor init(itemController: ItemController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.tableEditModel = TableEditModel()
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let tableEditModel: TableEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = TableModel
    
    var itemControllable: any ItemControllable { itemController }
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
        save(updated: editModel, message: String(localized: "Added Dice", bundle: .module))
    }
}

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> TableEntryModel {
        TableEntryModel(id: UUID(), name: name, content: content)
    }

    @MainActor func merge(itemId: UUID, entries: [TableEntryModel]) -> [TableEntryModel] {
        entriesMatchedByName(itemId: itemId, entries: entries)
    }
    // `merge(itemId:entries:recoverEntries:forceSave:)` uses `EntryDataEditable`'s
    // shared default (see CODE_AUDIT_EditItem §9.2) — this module's behavior was
    // identical to the default, so the hand-copied override was removed.
}
