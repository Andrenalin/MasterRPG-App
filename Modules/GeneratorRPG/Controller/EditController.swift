// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        self.fileUrlDataController = nil
    }
    
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
}

// MARK: - EditControllable

extension EditController: EditControllable {
    var itemControllable: any ItemControllable {
        itemController
    }
}
