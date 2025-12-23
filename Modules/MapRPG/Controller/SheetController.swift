// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetModel] = []
        if let photoId = model.photoId {
            entries.append(SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), level: level, type: .photo, name: "", description: "", entries: []))
        }
        entries.append(contentsOf: sheetEntries(for: itemId, level: level + 1))
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.itemDataModel.networkModule), level: level, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetModel] {
        guard level < 25 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.compactMap { entry in
            guard !entry.isHexGrid else { return nil }
            let name = entry.name
            let description = entry.content
            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.itemDataModel.networkModule), level: level, name: name, description: description, entries: [])
        }
    }
}
