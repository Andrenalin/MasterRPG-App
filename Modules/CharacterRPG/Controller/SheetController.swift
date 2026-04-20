// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController

    @MainActor
    func sheet(for itemId: UUID, entryId: UUID?, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        if let entryId {
            let entry = model[entryId]
            return sheetEntry(itemId: itemId, entry: entry, level: level, editMode: true)
        }

        var entries: [SheetFirstModel] = []
        let showHeader: Bool = model.displayState == 0
        
        if showHeader, let photoId = model.photoId {
            entries.append(SheetFirstModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: []))
        }
        entries.append(contentsOf: sheetEntries(for: itemId, level: level + 1))
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .item, showHeader: showHeader, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.map { entry -> SheetFirstModel in
            sheetEntry(itemId: itemId, entry: entry, level: level)
        }
    }
    
    @MainActor func sheetEntry(itemId: UUID, entry: ValueEntryModel, level: Int, editMode: Bool = false) -> SheetFirstModel {
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
        var inlineEntries: [SheetFirstModel] = []
        if let diceId = entry.diceId {
            inlineEntries.append(SheetFirstModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }

        let result = SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: editMode ? .edit : (entry.valueId == nil ? .item : .group), editType: entry.editType, name: name, description: description, inlineEntries: inlineEntries, entries: [])
        return result
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: nil, level: level, type: .photo, name: model.name, description: model.description, entries: [])
        return sheetModel
    }
}
