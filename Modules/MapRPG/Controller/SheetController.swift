// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
    
    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetFirstModel] = []
        if let photoId = model.photoId {
            entries.append(SheetFirstModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: []))
        }
        entries.append(contentsOf: sheetEntries(for: itemId, level: level + 1))
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 4 else { return [] }
        let value = itemController.itemOrEmpty(for: itemId)
        return value.entries.compactMap { entry in
            guard !entry.isHexGrid else { return nil }
            let name = entry.name
            let description = entry.content
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, inlineEntries: [
                SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), type: .photoInline, name: "", description: "", entries: [])
            ], entries: [])
        }
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetModel] = []

        if let photoId = model.photoId {
            entries.append(SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: []))
        }
        entries.append(contentsOf: sheetEntries(root: root, itemId: itemId, level: level + 1, isShown: isShown))

        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, type: .item, isShown: isShown, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, isShown: Bool) -> [SheetModel] {
        guard level < 4 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.compactMap { entry in
            guard !entry.isHexGrid else { return nil }
            return sheetEntry(root: root, itemId: itemId, entry: entry, level: level, isShown: isShown)
        }
    }

    @MainActor func sheetEntry(root: RootManager, itemId: UUID, entry: MapEntryModel, level: Int, isShown: Bool) -> SheetModel {
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let inlineEntries: [SheetModel] = [
            SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .photoInline, isShown: isShown, name: "", description: "", entries: [])
        ]

        let links = LinkReplaceController.links(for: description)
        let linkSheets = links.compactMap { link -> SheetModel? in
            switch link.module {
            case .map:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false)
                } else {
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false)
            }
        }

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .item, isShown: isShown, name: name, description: description, inlineEntries: inlineEntries, entries: linkSheets)
    }
}
