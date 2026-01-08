// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetModel] = []
        let showHeader: Bool = model.displayState == 0
        
//        if let parentId = model.parentId, let parentModel = itemController.itemSync(for: parentId) {
//            showHeader = parentModel.isFolder
//        }
        
        if showHeader, let photoId = model.photoId {
            entries.append(SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), level: level, type: .photo, name: "", description: "", entries: []))
        }
        entries.append(contentsOf: sheetEntries(for: itemId, level: level + 1))
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .item, showHeader: showHeader, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.flatMap { entry -> [SheetModel] in
            var name = entry.name
            var description = ""
            if let valueId = entry.valueId {
                let value = itemController.itemOrEmpty(for: valueId)
                name = ""
                description = value.url(linkNumber: 0)
            } else {
                description = entry.value
                if let valueCalculate = linkController.calculate(entry: entry), description != valueCalculate {
                    description += " = \(valueCalculate)"
                }
            }
            var inlineEntries: [SheetModel] = []
            if let diceId = entry.diceId {
                inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), level: level, type: .dice, name: "", description: "", entries: []))
            }

            let result = [SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, inlineEntries: inlineEntries, entries: [])]

            return result
        }
    }
}
