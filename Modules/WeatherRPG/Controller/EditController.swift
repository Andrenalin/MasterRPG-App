// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        self.fileUrlDataController = nil
        self.selectionPhoto = ItemSelectionModel()
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?

    let selectionPhoto: ItemSelectionModel
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
        duplicateDataModel(item: item, newItemId: newItemId)
    }
}

// MARK: - Module Editor

extension EditController {
    func add(photoId: UUID?, model: WeatherDataModel) {
        model.photoId = photoId
        try? model.modelContext?.save()
    }
}
