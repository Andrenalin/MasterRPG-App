// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.itemDataModel.networkModule), level: level, name: model.name, description: model.description, entries: sheetGroups(for: itemId, level: level + 1))
        return sheetModel
    }

    @MainActor
    func sheetGroups(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            var name = entry.name
            var entries: [SheetModel] = []

            var description = ""
            if let valueId = entry.valueId {
                let value = itemController.itemOrEmpty(for: valueId)
                name = value.name
                entries = [sheet(for: valueId, level: level + 1)]
            } else {
                description = entry.value
                if let valueCalculate = linkController.calculate(entry: entry), description != valueCalculate {
                    description += " = \(valueCalculate)"
                }
            }
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.itemDataModel.networkModule), level: level, name: name, description: description, entries: entries)
        }
    }
}
