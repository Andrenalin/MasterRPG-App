// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class TableEditModel: Sendable {
    var contentLinks: [UUID: LinkReplaceController] = [:]
    
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()

    func resetLinks() {
        contentLinks = [:]
    }
}

struct LinkTableModuleTransferable: LinkDataTransferable {
    public var module: NetworkModules
    public let itemId: UUID
    public let entryId: UUID?
    public let name: String

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .tableLink)
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

struct EditController: Sendable {
    @MainActor init(diceRoot: DiceRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.diceRoot = diceRoot
        
        self.itemController = itemController
        self.linkRegisterControllable = linkRegisterControllable
        
        self.editorModel = ItemEditorModel()
        self.tableEditModel = TableEditModel()
    }

    let diceRoot: DiceRootModel

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    
    let editorModel: ItemEditorModel
    let tableEditModel: TableEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = TableModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
            
    public var linkModules: [NetworkModules] { [.table, .dice] }
    
    public func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        module == .table || module == .dice
    }
    
    public func linkSelectionDestination(for entryId: UUID) -> any NavigationDestination {
        EditorRoute.linkSelection(entryId)
    }

    public func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination {
        switch module {
        case .dice:
            SelectionDiceRoute.selection
        default:
            SelectionTableRoute.selection
        }
    }

    func create(name: String, content: String) -> TableEntryModel {
        TableEntryModel(id: UUID(), name: name, content: content)
    }
}

// MARK: - Module Editor

extension EditController {
    @MainActor func add(diceId: UUID?, model: TableModel) {
        model.diceId = diceId
        save(with: "Add Dice")
    }
}

extension EditController {
    @MainActor func didSetModel() {}

    @MainActor
    func resetCurrentModel() {
        tableEditModel.resetLinks()
    }
    
    @MainActor 
    func submitChanges() {
        tableEditModel.resetLinks()
    }
}

// MARK: - Link Editor

extension EditController {
    @MainActor
    func contentEditLink(for entryId: UUID) -> LinkReplaceController {
        guard let controller = tableEditModel.contentLinks[entryId] else {
            let controller = LinkReplaceController {
                model[entryId].content
            } setter: {
                update(entryId: entryId, content: $0)
            }
            tableEditModel.contentLinks[entryId] = controller
            return controller
        }
        return controller
    }

    @MainActor
    func updateContent(_ content: String, for entryId: UUID) {
        if let contentLink = tableEditModel.contentLinks[entryId] {
            contentLink.editValue.wrappedValue = content
        } else {
            update(entryId: entryId, content: content)
        }
        save(with: String(localized: "Add link").localizedString)
    }
    
    @MainActor func update(entryId: UUID, content: String) {
        model[entryId].content = content
        editorModel.cacheItemListModel.reset(cacheType: .content, itemId: entryId, text: content)
        editorModel.cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: model[entryId].textLinkContent)
    }
}

extension EditController {
    @MainActor func merge(entries: [TableEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        let item = model
        var newEntries = entries.map { entry in
            let foundEntry = item.entries.first(where: { $0.name == entry.name })
            return TableEntryModel(id: foundEntry?.id ?? entry.id, name: entry.name, content: entry.content, displayState: entry.displayState, diceResult: entry.diceResult)
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
            save(with: String(localized: "Entries replaced").localizedString)
            return []
        }
        return itemRowModels
    }

//    @MainActor
//    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [TableEntryModel] {
//        guard let anotherIds else {
//            if module == .dice {
//                let otherEntries = diceRoot.linkController.link(for: .table)
//                return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
//            }
//            let otherEntries = root.linkController.link(for: .table)
//            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
//        }
//        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
//            switch module {
//            case .dice:
//                return diceRoot.linkController.linkEntries(for: anotherId)
//            case .table:
//                return root.linkController.linkEntries(for: anotherId)
//            default:
//                return []
//            }
//        }
//        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
//    }

    @MainActor
    func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [TableEntryModel] {
        guard let entries = itemController.itemSync(for: itemId)?.entries else { return [] }
        return entries.map { entry in
            var replacedEntry = entry
            linkEntries.forEach { linkEntry in
                replacedEntry = scanReplace(entry: replacedEntry, linkEntry: linkEntry, getLink: { $0.content }, setLink: { var result = $1; result.content = $0; return result }, caseInsensitive: caseInsensitive, words: words)
            }
            return replacedEntry
        }
    }
}
