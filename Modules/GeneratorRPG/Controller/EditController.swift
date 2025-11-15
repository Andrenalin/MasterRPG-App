// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        self.fileUrlDataController = nil
        self.selectionReference = ItemSelectionModel()
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
    
    let selectionReference: ItemSelectionModel
}

// MARK: - EditControllable

extension EditController: EditControllable {
    var itemControllable: any ItemControllable {
        itemController
    }
}

// MARK: - Module Editor

extension EditController {
    func add(referenceId: UUID?, model: GeneratorDataModel) {
        model.referenceId = referenceId
        try? model.modelContext?.save()
    }
}

