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
        guard level < 4 else { return [] }
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
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)

        let showHeader: Bool = model.displayState == 0

        var inlineEntries: [SheetModel] = []
        if showHeader, let photoId = model.photoId {
            inlineEntries = [SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: [])]
        }
        let isFolded = moduleDepth >= 1
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)

        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, type: .item, isShown: isShown, isFolded: isFolded, showHeader: showHeader, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: 0)
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        }
    }

    @MainActor private func sheet(entry: ValueEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> SheetModel {
        var name = entry.name
        var description = ""
        var sheetType: SheetModelType = .item

        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        var linkSheets: [SheetModel] = []

        if let valueId = entry.valueId {
            let value = itemController.itemOrEmpty(for: valueId)
            name = ""
            description = value.url(linkNumber: 0)
            sheetType = .group
            linkSheets = [sheet(root: root, itemId: valueId, destination: destination, level: level + 1, isShown: true, moduleDepth: moduleDepth)]
        } else {
            description = entry.value
            if let valueCalculate = linkController.calculate(entry: entry), description != valueCalculate {
                description += " = \(valueCalculate)"
            }
        }

        var inlineEntries: [SheetModel] = []
        if let diceId = entry.diceId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: []))
        }

        let links = LinkReplaceController.links(for: description)
        linkSheets.append(contentsOf: links.compactMap { link -> SheetModel? in
            switch link.module {
            case .value: // this should not happen
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1)
                } else {
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0)
            }
        })

        let result = SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: sheetType, editType: entry.editType, name: name, description: description, inlineEntries: inlineEntries, entries: linkSheets)
        return result
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: [])
    }

    @MainActor private func createDiceInline(diceId: UUID, itemId: UUID, entryId: UUID, level: Int) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: [])
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
        if model.displayState == 0 {
            if let photoId = model.photoId {
                let photoSource = ItemRowModel(itemId: photoId, typeId: .photo)
                let photoSheetModel = sheetModel.inlineEntries.first ?? createPhotoInline(photoId: photoId, itemId: model.id, level: sheetModel.level)
                photoSheetModel.source = photoSource
                sheetModel.inlineEntries = [photoSheetModel]
            } else {
                sheetModel.inlineEntries = []
            }
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
        for itemEntry in model.entries {
            if let existingSheetModel = sheetModel.entries.first(where: { $0.source.entryId == itemEntry.id }) {
                var name = itemEntry.name
                var description = ""

                if let valueId = itemEntry.valueId {
                    let value = itemController.itemOrEmpty(for: valueId)
                    name = ""
                    description = value.url(linkNumber: 0)
                } else {
                    description = itemEntry.value
                    if let valueCalculate = linkController.calculate(entry: itemEntry), description != valueCalculate {
                        description += " = \(valueCalculate)"
                    }
                }

                unequalSet(lhs: &existingSheetModel.name, rhs: name) { changed in
                    existingSheetModel.hasChanged = changed
                }
                unequalSet(lhs: &existingSheetModel.description, rhs: description) { changed in
                    existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
                }

                // Update inline entries (dice)
                if let diceId = itemEntry.diceId {
                    let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
                    let diceSheetModel = existingSheetModel.inlineEntries.first ?? createDiceInline(diceId: diceId, itemId: model.id, entryId: itemEntry.id, level: sheetModel.level)
                    diceSheetModel.source = diceSource
                    existingSheetModel.inlineEntries = [diceSheetModel]
                } else {
                    existingSheetModel.inlineEntries = []
                }

                // Update linked value sheets and other nested sheets
                existingSheetModel.entries.forEach { subSheetModel in
                    root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel)
                }

                updatedEntries.append(existingSheetModel)
            } else {
                updatedEntries.append(sheet(entry: itemEntry, root: root, itemId: model.id, level: sheetModel.level + 1, moduleDepth: 0))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
