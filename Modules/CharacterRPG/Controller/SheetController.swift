// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController
    let linkController: LinkController

    // Timing accumulators for performance comparison
    @MainActor private static var parseDurationTotal: Duration = .zero
    @MainActor private static var registerDurationTotal: Duration = .zero
}

extension SheetController: SheetControllable {
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }

    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let startTime = ContinuousClock.now

        // Reset timing counters at the start of a new sheet tree
        if level == 0 {
            Self.parseDurationTotal = .zero
            Self.registerDurationTotal = .zero
            Logger.sheetController.info("🚀 [Sheet] Starting sheet creation \(itemController.config.module.token) - itemId: \(itemId.uuidString)")
        }
        
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []
        var totalSheetCount = 1 // Count this sheet
        
        if let diceId = model.diceId {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level, isShown: isShown))
            totalSheetCount += 1
        }

        if let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
            totalSheetCount += 1
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        
        // Count all nested sheets
        let nestedCount = countSheets(in: entries)
        totalSheetCount += nestedCount
        
        let showHeader = model.displayState == 0
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, showHeader: showHeader, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)

        // Report timing only at the root level
        if level == 0 {
            let duration = ContinuousClock.now - startTime
            Logger.sheetController.info("✅ [Sheet] Completed \(itemController.config.module.token) - Duration: \(duration), Sheets: \(totalSheetCount), ParseLinks: \(Self.parseDurationTotal), RegisterLinks: \(Self.registerDurationTotal)")
        }

        return sheetModel
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

        // Measure and compare both link parsing approaches
        let parseStartTime = ContinuousClock.now
        let parsedLinks = LinkReplaceController.links(for: entry.content)
        let parseDuration = ContinuousClock.now - parseStartTime
        Self.parseDurationTotal += parseDuration

        let registerStartTime = ContinuousClock.now
        let registeredLinks = linkRegisterController.linksFrom(source: destination)
        let registerDuration = ContinuousClock.now - registerStartTime
        Self.registerDurationTotal += registerDuration

        // Use parsed links (existing behavior)
        let links = parsedLinks

        // Check if results match by comparing ItemRowModels
        let registeredDestinations = Set(registeredLinks.map { $0.destination })
        let parsedDestinations = Set(parsedLinks.map { ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module) })
        if registeredDestinations != parsedDestinations {
            Logger.sheetController.warning("[Sheet] Link mismatch! Entry: '\(name)', Parsed: \(parsedDestinations.count), Registered: \(registeredDestinations.count)")
        }

        let linkSheets = links.compactMap { link -> SheetModel? in
            switch link.module {
            case .value:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)
            }
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
    
    // Helper function to count all sheets in a tree
    @MainActor private func countSheets(in sheets: [SheetModel]) -> Int {
        var count = sheets.count
        for sheet in sheets {
            count += countSheets(in: sheet.inlineEntries)
            count += countSheets(in: sheet.entries)
        }
        return count
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
        
        let (name, description) = entryNameDescription(entry: entry, root: root)
        unequalSet(lhs: &existingSheetModel.name, rhs: name) { changed in
            existingSheetModel.hasChanged = changed
        }
        unequalSet(lhs: &existingSheetModel.description, rhs: description) { changed in
            existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
        }
        unequalSet(lhs: &existingSheetModel.editType, rhs: entry.editType) { changed in
            existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
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
        existingSheetModel.entries.forEach { subSheetModel in
            root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel, isEditor: isEditor)
        }
        return existingSheetModel
    }
}
