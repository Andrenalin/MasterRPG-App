// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    @MainActor
    init(itemControllable: any ItemControllable, fileUrlDataController: FileUrlDataController? = nil) {
        self.itemControllable = itemControllable
        self.fileUrlDataController = fileUrlDataController
        self.selectionPhoto = ItemSelectionModel()
    }
    
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
    
    let selectionPhoto: ItemSelectionModel
}
