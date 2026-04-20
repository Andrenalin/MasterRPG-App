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
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        if let diceId = model.diceId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }
        let entries: [SheetModel] = sheetEntries(root: root, itemId: itemId, level: level)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 2 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)
            
            let links = LinkReplaceController.links(for: entry.content)
            let linkSheets = links.compactMap { link -> SheetModel? in
                switch link.module {
                case .dice:
                    return nil
                case .pdf:
                    return SheetModel(source: ItemRowModel(itemId: link.itemId, entryId: link.entryId, typeId: link.module), level: level + 1, name: link.name, description: "", entries: [])
                default:
                    if link.entryId == nil {
                        return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1)
                    } else {
                        return nil
                    }
                }
            }
            
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: linkSheets)
        }
    }
}
