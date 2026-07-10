// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController {
    let itemController: ItemController
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []
        inlineEntries.append(SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .pdf, isShown: isShown, name: "", description: "", entries: []))

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, canAdd: false, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: 0)
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> [SheetModel] {
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        return item.entries.map { entry in
            let name = entry.name
            let description = entry.content
            let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

            let inlineEntries: [SheetModel] = [
                SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .pdf, name: "", description: "", entries: [])
            ]

            return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, name: name, description: description, inlineEntries: inlineEntries, entries: [])
        }
    }

    @MainActor private func sheetEntry(itemId: UUID, entry: PdfEntryModel, level: Int) -> SheetModel {
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let inlineEntries: [SheetModel] = [
            SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .pdf, name: "", description: "", entries: [])
        ]

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, name: name, description: description, inlineEntries: inlineEntries, entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: sheetModel.source.itemId)

        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
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
                updatedEntries.append(existingSheetModel)
            } else {
                updatedEntries.append(sheetEntry(itemId: model.id, entry: entry, level: sheetModel.level))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
