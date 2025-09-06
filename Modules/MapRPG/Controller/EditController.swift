// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    @MainActor
    init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
        self.selectionDice = ItemSelectionModel()
        self.selectionPhoto = ItemSelectionModel()
    }
    
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController? = nil
    
    let selectionDice: ItemSelectionModel
    let selectionPhoto: ItemSelectionModel
}

extension EditController {
    func add(photoId: UUID?, model: MapDataModel) {
        model.photoId = photoId
        try? model.modelContext?.save()
    }
}
