// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        
        let inlineEntries = [SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: [])]
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, type: .photo, isShown: isShown, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: [])
        return sheetModel
    }
}
