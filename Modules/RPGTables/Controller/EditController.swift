// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import SwiftUI
import RPGDie

@MainActor @Observable
final class TableEditModel: Sendable {
    var contentLinks: [UUID: LinkReplaceController] = [:]
    
    let pdfSelectionModel = SelectionModel(id: UUID(), filter: .all)

    func resetLinks() {
        contentLinks = [:]
    }
}

struct EditController: Sendable {
    @MainActor
    init(root: TableRoot, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
        self.tableEditModel = TableEditModel()
    }

    weak var root: TableRoot!
    var fileUrlDataController: FileUrlDataController? = nil
    let editorModel: ItemEditorModel
    let tableEditModel: TableEditModel
}

extension EditController: EntryDataEditable {
    
    typealias Model = TableModel

    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var linkRegisterControllable: any LinkRegisterControllable {
        root.linkRegisterControllable
    }

    @MainActor func didSetModel() {
        guard let id = editorModel.currentItemId else { return }
        if tableEditModel.pdfSelectionModel.id != id {
            tableEditModel.pdfSelectionModel.id = id
        }
    }

    @MainActor
    func resetCurrentModel() {
        tableEditModel.resetLinks()
    }
    
    @MainActor 
    func submitChanges() {
        tableEditModel.resetLinks()
    }
}

// MARK: - Selection

extension EditController {
    @MainActor @ViewBuilder
    func selectDice(for entryId: UUID, linkKeyPath: WritableKeyPath<TableModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.diceRoot.viewController.viewSelect(filter: .table) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .dice) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.diceRoot.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change dice links").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor 
    func selectDice(dismissAction: @escaping () -> Void) -> some View {
        root.diceRoot.viewController.viewSelect(filter: .table) {
            if let diceId = self.model.diceId {
                return [ItemRowModel(itemId: diceId, typeId: .dice)]
            } else {
                return []
            }
        } toggleSelection: { selection, _ in
            if self.model.diceId == selection.itemId {
                self.model.diceId = nil
            } else {
                self.model.diceId = selection.itemId
            }
            self.save(with: String(localized: "Change dice link").localizedString)
        } dismissAction: {
            dismissAction()
        }
    }

    @MainActor @ViewBuilder
    func selectTable(for entryId: UUID, linkKeyPath: WritableKeyPath<TableModel, String>, dismissAction: @escaping () -> Void) -> some View {
        root.viewController.viewSelect(filter: .all) {
            let text = self.model[keyPath: linkKeyPath]
            return self.model.links(for: text).map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: .table) }
        } toggleSelection: { sel, _ in
            self.model[keyPath: linkKeyPath] = self.root.linkController.generateLinks(itemId: sel.itemId, entryId: sel.entryId, into: self.model[keyPath: linkKeyPath])
            self.save(with: String(localized: "Change table links").localizedString)
        } dismissAction: {
            dismissAction()
        }
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
    @MainActor
    func merge(entries: [TableEntryModel], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel] {
        let item = model
        var newEntries = entries.map { entry in
            let foundEntry = item.entries.first(where: { $0.name == entry.name })
            return TableEntryModel(id: foundEntry?.id ?? entry.id, name: entry.name, content: entry.content, displayState: entry.displayState, diceResult: entry.diceResult)
        }
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = root.itemController.itemDataModel.networkModule
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.id, entryId: $0, typeId: module) }

        var effectedLinks = true
        for itemRowModel in itemRowModels {
            if !root.itemController.usedLinks(for: itemRowModel).isEmpty {
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

    @MainActor
    func scan(itemId: UUID, with anotherIds: [UUID]?, module: NetworkModules, caseInsensitive: Bool, words: Bool) -> [TableEntryModel] {
        guard let anotherIds else {
            if module == .dice {
                let otherEntries = root.diceRoot.linkController.link(for: .table)
                return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
            }
            let otherEntries = root.linkController.link(for: .table)
            return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
        }
        let otherEntries: [LinkEntryModel] = anotherIds.flatMap { anotherId in
            switch module {
            case .dice:
                return root.diceRoot.linkController.linkEntries(for: anotherId)
            case .table:
                return root.linkController.linkEntries(for: anotherId)
            default:
                return []
            }
        }
        return scan(itemId: itemId, with: otherEntries, caseInsensitive: caseInsensitive, words: words)
    }

    @MainActor
    func scan(itemId: UUID, with linkEntries: [LinkEntryModel], caseInsensitive: Bool, words: Bool) -> [TableEntryModel] {
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
