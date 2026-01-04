// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetModel] = []
        entries.append(SheetModel(source: ItemRowModel(itemId: itemId, typeId: .pdf), level: level, type: .photo, name: "", description: "", entries: []))
        entries.append(contentsOf: sheetEntries(for: itemId, level: level))
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, canAdd: false, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
    }
}
