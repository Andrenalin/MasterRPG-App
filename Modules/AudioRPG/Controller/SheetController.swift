// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController

    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetFirstModel] = []
        if model.hasAudio {
            entries.append(SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .audioInline, name: model.name, description: model.description, entries: []))
        }
        entries.append(contentsOf: sheetEntries(for: itemId, level: level))
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, canAdd: false, showHeader: false, name: model.name, description: model.description, entries: entries)
        return sheetModel
    }
    
    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 4 else { return [] }
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let track = itemController.itemOrEmpty(for: entry.audioId)
            var name = track.name
            let description = track.description
            if track.specialCategory {
                name = track.url(linkNumber: 0)
            }
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: .audioInline, name: name, description: description, entries: [])
        }
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        if model.hasAudio {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .audioInline, isShown: isShown, name: model.name, description: model.description, entries: []))
        }

        let isFolded = moduleDepth >= 1
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, canAdd: false, showHeader: false, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: 0)
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            let track = itemController.itemOrEmpty(for: entry.audioId)
            var name = track.name
            let description = track.description
            if track.specialCategory {
                name = track.url(linkNumber: 0)
            }

            let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

            let links = LinkReplaceController.links(for: description)
            let linkSheets = links.compactMap { link -> SheetModel? in
                switch link.module {
                case .audio:
                    if link.entryId == nil {
                        return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1)
                    } else {
                        return nil
                    }
                default:
                    return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0)
                }
            }

            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .audioInline, name: name, description: description, entries: linkSheets)
        }
    }
}
