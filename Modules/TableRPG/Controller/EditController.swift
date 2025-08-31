// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    @MainActor
    init(itemControllable: any ItemControllable, fileUrlDataController: FileUrlDataController? = nil) {
        self.itemControllable = itemControllable
        self.fileUrlDataController = fileUrlDataController
        self.selectionDice = ItemSelectionModel()
    }
    
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
    
    let selectionDice: ItemSelectionModel
}

extension EditController {
    func add(diceId: UUID?, model: TableDataModel) {
        model.diceId = diceId
        try? model.modelContext?.save()
    }
}
