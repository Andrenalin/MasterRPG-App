// @copyright André Trettin

import AndrenalinKit
import Foundation

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        let sheetModel = SheetModel(id: itemId, name: model.name, description: model.description, groups: sheetGroups(for: itemId, level: level))
        return sheetModel
    }

    @MainActor
    func sheetGroups(for itemId: UUID, level: Int) -> [SheetGroupModel] {
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            var name = entry.name.withoutLink()
            var description = entry.value
            if let valueId = entry.valueId {
                let value = itemController.itemOrEmpty(for: valueId)
                name = value.name
                description = ""
            }
            let entries = sheetEntries(for: entry).dropFirst()
            return SheetGroupModel(id: UUID(), name: name, description: description, level: level, entries: Array(entries))
        }
    }
    
    @MainActor
    func sheetEntries(for entry: ValueEntryModel, deep: Int = 0) -> [SheetEntryModel] {
        guard deep < 20 else { return [] }
        var value = entry.value
        if let valueCalculate = linkController.calculate(entry: entry), value != valueCalculate {
            value += " = \(valueCalculate)"
        }
        var entries = [SheetEntryModel(id: UUID(), name: entry.name.withoutLink(), value:  value)]
        
        if let valueId = entry.valueId {
            let model = itemController.itemOrEmpty(for: valueId)
            let subEntries = model.entries.flatMap { sheetEntries(for: $0, deep: deep + 1) }
            entries.append(contentsOf: subEntries)
        }
        return entries
    }
}
