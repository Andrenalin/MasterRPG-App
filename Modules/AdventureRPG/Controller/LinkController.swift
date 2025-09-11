// @copyright André Trettin

import CoreRPG
import Foundation

struct LinkController: Sendable {
    var module: NetworkModules
    var itemController: ItemController
    
    var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {    
    @MainActor func validate(itemId: UUID, entryId: UUID?) -> Bool {
        guard let model = itemController.model(for: itemId) else { return false }
        return model.entries.contains(where: { $0.entryId == entryId })
    }
}
