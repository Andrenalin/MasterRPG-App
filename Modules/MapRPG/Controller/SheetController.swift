// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.itemDataModel.networkModule), level: level, name: model.name, description: model.description, entries: sheetGroups(for: itemId, level: level + 1))
        return sheetModel
    }

    @MainActor func sheetGroups(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.itemDataModel.networkModule), level: level, name: name, description: description, entries: [])
        }
    }
}
