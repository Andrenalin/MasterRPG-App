// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        guard let model = itemController.modelSync(for: itemId) else { return SheetModel(id: itemId) }
        let sheetModel = SheetModel(id: itemId, name: model.name, description: model.information, groups: sheetGroups(for: itemId, level: level))
        return sheetModel
    }
    
    @MainActor
    func sheetGroups(for itemId: UUID, level: Int) -> [SheetGroupModel] {
        guard let value = itemController.model(for: itemId) else { return [] }
        return value.entries.map { entry in
            let name = entry.name.withoutLink()
            let description = entry.content
            let entries = sheetEntries(for: entry).dropFirst()
            return SheetGroupModel(id: UUID(), name: name, description: description, level: level, entries: Array(entries))
        }
    }
    
    @MainActor
    func sheetEntries(for entry: TableEntryDataModel, deep: Int = 0) -> [SheetEntryModel] {
        guard deep < 20 else { return [] }
        let value = entry.content
        let entries = [SheetEntryModel(id: UUID(), name: entry.name.withoutLink(), value: value)]
        return entries
    }
}
