// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        self.fileUrlDataController = nil
        self.selectionDice = ItemSelectionModel()
        self.selectionPdf = ItemSelectionModel()
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
    
    let selectionDice: ItemSelectionModel
    let selectionPdf: ItemSelectionModel
}

// MARK: - EditControllable

extension EditController: EditControllable {
    var itemControllable: any ItemControllable {
        itemController
    }
    
    func duplicate(item: ItemDataModel) {
        guard let model = itemController.model(for: item.id) else { return }
        let newItemId = UUID()
        let duplicat = model.duplicate(newItemId: newItemId)
        let modelContext = itemController.container.mainContext
        modelContext.insert(duplicat)
        try? modelContext.save()
        duplicat.entries.forEach { entry in
            let updatedName = linkRegisterController.replaceLinks(in: entry.name, newItemId: newItemId, newEntryId: entry.entryId)
            entry.name <=> updatedName
            let updatedContent = linkRegisterController.replaceLinks(in: entry.content, newItemId: newItemId, newEntryId: entry.entryId)
            entry.content <=> updatedContent
        }
        duplicateDataModel(item: item, newItemId: newItemId)
    }
}

// MARK: - Module Editor

extension EditController {
    func add(diceId: UUID?, model: CharacterDataModel) {
        model.diceId = diceId
        try? model.modelContext?.save()
    }
}
