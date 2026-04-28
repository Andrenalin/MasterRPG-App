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
        return value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        if let photoId = model.photoId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: []))
        }

        let isFolded = moduleDepth >= 3
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: 0)
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            sheetEntry(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        }
    }

    @MainActor private func sheetEntry(entry: AdventureEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> SheetModel {
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let links = LinkReplaceController.links(for: entry.content)
        let linkSheets = links.compactMap { link -> SheetModel? in
            switch link.module {
            case .adventure:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1)
                } else {
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0)
            }
        }

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: linkSheets)
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel) {
        let model = itemController.itemOrEmpty(for: sheetModel.source.itemId)

        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
        }

        // Update inline entries (photo)
        if let photoId = model.photoId {
            let photoSource = ItemRowModel(itemId: photoId, typeId: .photo)
            let photoSheetModel = sheetModel.inlineEntries.first ?? createPhotoInline(photoId: photoId, itemId: model.id, level: sheetModel.level, isShown: sheetModel.isShown)
            photoSheetModel.source = photoSource
            sheetModel.inlineEntries = [photoSheetModel]
        } else {
            sheetModel.inlineEntries = []
        }

        guard !sheetModel.isFolded else { return }
        let entryIds = model.entries.map { $0.id }

        // Remove deleted entries
        sheetModel.entries.removeAll { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }

        var updatedEntries: [SheetModel] = []
        for entry in model.entries {
            if let existingSheetModel = sheetModel.entries.first(where: { $0.source.entryId == entry.id }) {
                unequalSet(lhs: &existingSheetModel.name, rhs: entry.name) { changed in
                    existingSheetModel.hasChanged = changed
                }
                unequalSet(lhs: &existingSheetModel.description, rhs: entry.content) { changed in
                    existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
                }
                existingSheetModel.entries.forEach { subSheetModel in
                    root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel)
                }
                updatedEntries.append(existingSheetModel)
            } else {
                updatedEntries.append(sheetEntry(entry: entry, root: root, itemId: model.id, level: sheetModel.level, moduleDepth: 0))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
