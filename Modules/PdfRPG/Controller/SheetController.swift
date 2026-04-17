// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetFirstModel] = []
        entries.append(SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: []))
        entries.append(contentsOf: sheetEntries(for: itemId, level: level))
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, canAdd: false, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 25 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let name = entry.name
            let description = entry.content
            let inlineEntries: [SheetFirstModel] = [
                SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: .pdf, name: "", description: "", entries: [])
            ]
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, inlineEntries: inlineEntries, entries: [])
        }
    }
}
