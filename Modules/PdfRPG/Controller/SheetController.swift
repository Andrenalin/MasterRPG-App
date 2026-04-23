// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetFirstModel] = []
        entries.append(SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: []))
        entries.append(contentsOf: sheetFirstEntries(for: itemId, level: level))
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, canAdd: false, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetFirstEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 25 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let name = entry.name
            let description = entry.content
            let inlineEntries: [SheetFirstModel] = [
                SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: .pdf, name: "", description: "", entries: [])
            ]
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, inlineEntries: inlineEntries, entries: [])
        }
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)

        var entries: [SheetModel] = []
        entries.append(SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: []))
        entries.append(contentsOf: sheetEntries(root: root, itemId: itemId, level: level, isShown: isShown))
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, canAdd: false, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, isShown: Bool) -> [SheetModel] {
        guard level < 25 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let name = entry.name
            let description = entry.content
            let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

            let inlineEntries: [SheetModel] = [
                SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .pdf, isShown: isShown, name: "", description: "", entries: [])
            ]

            let links = LinkReplaceController.links(for: description)
            let linkSheets = links.compactMap { link -> SheetModel? in
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false)
            }

            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, name: name, description: description, inlineEntries: inlineEntries, entries: linkSheets)
        }
    }
}
