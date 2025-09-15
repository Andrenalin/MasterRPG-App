// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController? = nil) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
        self.selectionDice = ItemSelectionModel()
        self.selectionPdf = ItemSelectionModel()
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
    
    let selectionDice: ItemSelectionModel
    let selectionPdf: ItemSelectionModel
}

extension EditController: EditControllable {
    var itemControllable: any ItemControllable {
        itemController
    }
    
    func add(diceId: UUID?, model: TableDataModel) {
        model.diceId = diceId
        try? model.modelContext?.save()
    }
    
    @MainActor func duplicate(item: ItemDataModel) {
        guard let model = itemController.model(for: item.id) else { return }
        let newItemId = UUID()
        let duplicat = model.duplicate(newItemId: newItemId)
        let modelContext = itemController.container.mainContext
        modelContext.insert(duplicat)
        try? modelContext.save()
        duplicat.entries.forEach { entry in
            let updatedContent = linkRegisterController.replaceLinks(in: entry.content, newItemId: newItemId, newEntryId: entry.entryId)
            entry.content <=> updatedContent
        }
        duplicateDataModel(item: item, newItemId: newItemId)
    }
}

// MARK: Quick Editor

extension EditController {
    @MainActor
    func merge(entries: [TableEntryDataModel.TableEntryDataModelCodable], into model: TableDataModel, recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
        let item = model
        var newEntries = entries.enumerated().map { (index, entry) in
            if let foundEntry = item.entries.first(where: { $0.name == entry.name }) {
                foundEntry.replace(entry)
                return foundEntry
            } else {
                let newEntry = TableEntryDataModel(entry)
                model.modelContext?.insert(newEntry)
                return newEntry
            }
        }
        let removedIds = Set(item.entries.map { $0.entryId }).subtracting(newEntries.map { $0.entryId })
        let module = NetworkModules.table
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.itemId, entryId: $0, typeId: module) }

        var effectedLinks = true
        for itemRowModel in itemRowModels {
//            if !itemControllable.usedLinks(for: itemRowModel).isEmpty {
//                effectedLinks = false
//                break;
//            }
        }
        if recoverEntries != nil || effectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            try? item.modelContext?.save()
            return []
        }
        return itemRowModels
    }
}
