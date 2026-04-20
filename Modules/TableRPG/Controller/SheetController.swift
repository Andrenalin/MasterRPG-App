// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
    @MainActor func sheetFirstModel(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetFirstModel] = []
        if let diceId = model.diceId {
            inlineEntries.append(SheetFirstModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }
        let entries: [SheetFirstModel] = sheetFirstEntries(for: itemId, level: level)
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetFirstEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        if let diceId = model.diceId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }
        let entries: [SheetModel] = sheetEntries(for: itemId, level: level)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 50 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            
            let links = LinkReplaceController.links(for: entry.content)
            let linkSheets = links.map {
                switch $0.module {
                case .dice:
                    SheetModel(source: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), level: level + 1, name: $0.name, description: "", entries: [])
                case .pdf:
                    SheetModel(source: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), level: level + 1, name: $0.name, description: "", entries: [])
                default:
                    sheet(for: $0.itemId, level: level + 1)
                }
            }
            
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: linkSheets)
        }
    }
}
