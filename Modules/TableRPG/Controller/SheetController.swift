// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetFirstModel] = []
        if let diceId = model.diceId {
            inlineEntries.append(SheetFirstModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }
        let entries: [SheetFirstModel] = sheetEntries(for: itemId, level: level)
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
    }
}
