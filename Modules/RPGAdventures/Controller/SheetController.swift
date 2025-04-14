// @copyright André Trettin

import AndrenalinKit
import Foundation

struct SheetController {
    init(root: AdventureRoot) {
        self.root = root
    }
    
    weak var root: AdventureRoot!

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = root.itemController.itemOrEmpty(for: itemId)
        let sheetModel = SheetModel(id: itemId, name: model.name, description: model.description, groups: sheetGroups(for: itemId, level: level))
        return sheetModel
    }

    @MainActor
    func sheetGroups(for itemId: UUID, level: Int) -> [SheetGroupModel] {
        let value = root.itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name.withoutLink()
            let description = entry.content
            let entries = sheetEntries(for: entry).dropFirst()
            return SheetGroupModel(id: UUID(), name: name, description: description, level: level, entries: Array(entries))
        }
    }
    
    @MainActor
    func sheetEntries(for entry: AdventureEntryModel, deep: Int = 0) -> [SheetEntryModel] {
        guard deep < 20 else { return [] }
        let value = entry.content
//        if let valueCalculate = root.linkController.calculate(entry: entry), value != valueCalculate {
//            value += " = \(valueCalculate)"
//        }
        let entries = [SheetEntryModel(id: UUID(), name: entry.name.withoutLink(), value: value)]
        
//        if let valueId = entry.valueId {
//            let model = root.itemController.itemOrEmpty(for: valueId)
//            let subEntries = model.entries.flatMap { sheetEntries(for: $0, deep: deep + 1) }
//            entries.append(contentsOf: subEntries)
//        }
        return entries
    }
}
