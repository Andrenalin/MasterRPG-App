// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        if let diceId = model.diceId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: .table), level: level, type: .dice, name: "", description: "", entries: []))
        }
        let entries: [SheetModel] = sheetEntries(for: itemId, level: level)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
    }
}
