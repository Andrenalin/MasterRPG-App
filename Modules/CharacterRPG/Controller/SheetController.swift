// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController
}

extension SheetController: SheetControllable {
    @MainActor var linkRegisterController: LinkRegisterController { itemController.linkRegisterController }

    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []
        
        if let diceId = model.diceId {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level, isShown: isShown))
        }

        if let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        
        let showHeader = model.displayState == 0
        return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, showHeader: showHeader, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        let sheets = item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
        return sheets
    }
    
    @MainActor private func sheet(entry: ValueEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)
        let (name, description) = entryNameDescription(entry: entry, root: root)

        var inlineEntries: [SheetModel] = []
        if let diceId = entry.diceId {
            inlineEntries.append(SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: destination, level: level, type: .dice, name: "", description: "", entries: []))
        }

        var allSheets: [SheetModel] = []
        if let subValueId = entry.valueId {
            allSheets = [sheet(root: root, itemId: subValueId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)]
        }

        let links = linkRegisterController.linksFrom(source: destination)

        let linkSheets = links.compactMap { link -> SheetModel? in
            guard link.isSheetLink else { return nil }
            let linkDestination = link.destination
            let linkedSheet: SheetModel?
            switch linkDestination.typeId {
            case .value:
                if linkDestination.entryId == nil {
                    linkedSheet = sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    linkedSheet = nil
                }
            default:
                linkedSheet = root.rootModel(for: linkDestination.typeId)?.sheetControllable.sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)
            }
            linkedSheet?.linkNumber = link.linkNumber
            return linkedSheet
        }
        allSheets.append(contentsOf: linkSheets)

        let entryType: SheetModelType = entry.valueId != nil ? .group : .item
        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: entryType, editType: entry.editType, name: name, description: description, inlineEntries: inlineEntries, entries: allSheets)
    }

    @MainActor func entryNameDescription(entry: ValueEntryModel, root: RootManager) -> (name: String, description: String) {
        var name = entry.name
        var description = ""
        if let valueId = entry.valueId {
            let value = itemController.reviewAwareItemOrEmpty(root: root, for: valueId)
            name = value.url(linkNumber: 0)
        } else {
            description = entry.value
            if let valueCalculate = linkController.calculate(entry: entry), description != valueCalculate {
                description += " = \(valueCalculate)"
            }
        }
        return (name, description)
    }
    
    @MainActor private func createDiceInline(diceId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🔄 [Update] Starting update \(itemController.config.module.token) for itemId: \(sheetModel.source.itemId.uuidString), level: \(sheetModel.level)")
        
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: sheetModel.source.itemId)

        var changeCount = 0
        var updatedInlineEntries: [SheetModel] = []

        if let diceId = item.diceId {
            let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
            // Reuse existing if found, otherwise create new
            let diceSheetModel = sheetModel.inlineEntries.first(where: { $0.sheetType == .dice }) ?? createDiceInline(diceId: diceId, itemId: item.id, level: sheetModel.level, isShown: sheetModel.isShown)
            diceSheetModel.source = diceSource
            updatedInlineEntries.append(diceSheetModel)
        }

        if let photoId = item.photoId {
            let photoSource = ItemRowModel(itemId: photoId, typeId: .photo)
            // Reuse existing if found, otherwise create new
            let photoSheetModel = sheetModel.inlineEntries.first(where: { $0.sheetType == .photo }) ?? createPhotoInline(photoId: photoId, itemId: item.id, level: sheetModel.level, isShown: sheetModel.isShown)
            photoSheetModel.source = photoSource
            updatedInlineEntries.append(photoSheetModel)
        }

        // Only update if the array actually changed to avoid unnecessary SwiftUI updates
        if sheetModel.inlineEntries.count != updatedInlineEntries.count ||
           !zip(sheetModel.inlineEntries, updatedInlineEntries).allSatisfy({ $0.id == $1.id }) {
            sheetModel.inlineEntries = updatedInlineEntries
        }

        if !sheetModel.isFolded {
            updateEntries(item: item, root: root, in: sheetModel, isEditor: isEditor)
        }

        unequalSet(lhs: &sheetModel.name, rhs: item.name) { changed in
            sheetModel.hasChanged = changed
            if changed { changeCount += 1 }
        }
        unequalSet(lhs: &sheetModel.description, rhs: item.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
            if changed { changeCount += 1 }
        }

        let duration = ContinuousClock.now - startTime
        Logger.sheetController.info("✅ [Update] Completed - Duration: \(duration), Total entries: \(item.entries.count)")
    }
    
    @MainActor private func updateEntries(item: ValueModel, root: RootManager, in sheetModel: SheetModel, isEditor: Bool) {
        let entryIds = item.entries.map { $0.id }
        
        sheetModel.entries.removeAll { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }
        
        var updatedEntries: [SheetModel] = []
        
        for entry in item.entries {
            let updated = update(entry: entry, item: item, root: root, in: sheetModel, isEditor: isEditor)
            updatedEntries.append(updated)
        }
        sheetModel.entries = updatedEntries
    }
    
    @MainActor private func update(entry: ValueEntryModel, item: ValueModel, root: RootManager, in sheetModel: SheetModel, isEditor: Bool) -> SheetModel {
        guard let existingSheetModel = sheetModel.entries.first(where: { $0.source.entryId == entry.id }) else {
            return sheet(entry: entry, root: root, itemId: item.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor)
        }

        // Re-project the entry from scratch so a newly attached/removed sub-value or link
        // (e.g. converting the entry to a group) is reflected in sheetType and entries,
        // not just in name/description.
        let projectedEntry = sheet(entry: entry, root: root, itemId: item.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor)

        unequalSet(lhs: &existingSheetModel.name, rhs: projectedEntry.name) { changed in
            existingSheetModel.hasChanged = changed
        }
        unequalSet(lhs: &existingSheetModel.description, rhs: projectedEntry.description) { changed in
            existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
        }
        unequalSet(lhs: &existingSheetModel.editType, rhs: entry.editType) { changed in
            existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
        }
        if existingSheetModel.sheetType != projectedEntry.sheetType {
            existingSheetModel.sheetType = projectedEntry.sheetType
            existingSheetModel.hasChanged = true
        }
        // Update per-entry dice inline
        if let diceId = entry.diceId {
            let destination = ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemController.config.module)
            let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
            let diceSheetModel = existingSheetModel.inlineEntries.first(where: { $0.sheetType == .dice }) ?? SheetModel(source: diceSource, destination: destination, level: sheetModel.level, type: .dice, name: "", description: "", entries: [])
            diceSheetModel.source = diceSource
            existingSheetModel.inlineEntries = [diceSheetModel]
        } else {
            existingSheetModel.inlineEntries = []
        }

        var unmatchedExisting = existingSheetModel.entries
        let reconciledEntries = projectedEntry.entries.map { projectedChild -> SheetModel in
            guard let existingIndex = unmatchedExisting.firstIndex(where: {
                $0.source == projectedChild.source && $0.linkNumber == projectedChild.linkNumber
            }) else {
                existingSheetModel.hasChanged = true
                return projectedChild
            }

            let existingChild = unmatchedExisting.remove(at: existingIndex)
            existingChild.destination = projectedChild.destination
            existingChild.linkNumber = projectedChild.linkNumber
            root.rootModel(for: existingChild.source.typeId)?.sheetControllable.update(root: root, sheetModel: existingChild, isEditor: isEditor)
            return existingChild
        }
        if !unmatchedExisting.isEmpty {
            existingSheetModel.hasChanged = true
        }
        existingSheetModel.entries = reconciledEntries

        return existingSheetModel
    }
}
