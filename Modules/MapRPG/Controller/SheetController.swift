// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
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
            let name = entry.name.withoutLink()
            let description = entry.content
            let entries = sheetEntries(for: entry).dropFirst()
            return SheetGroupModel(id: UUID(), name: name, description: description, level: level, entries: Array(entries))
        }
    }
    
    @MainActor
    func sheetEntries(for entry: MapEntryModel, deep: Int = 0) -> [SheetEntryModel] {
        guard deep < 20 else { return [] }
        let value = entry.content
        let entries = [SheetEntryModel(id: UUID(), name: entry.name.withoutLink(), value: value)]
        return entries
    }
}
