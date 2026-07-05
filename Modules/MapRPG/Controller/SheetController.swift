// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController

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

        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        var totalSheetCount = 1 // Count this sheet

        if let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
            totalSheetCount += 1
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)

        // Count all nested sheets
        let nestedCount = countSheets(in: entries)
        totalSheetCount += nestedCount

        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)

        // Report timing only at the root level
        if level == 0 {
            let duration = ContinuousClock.now - startTime
            Logger.sheetController.info("✅ [Sheet] Completed \(itemController.config.module.token) - Duration: \(duration), Sheets: \(totalSheetCount), ParseLinks: \(Self.parseDurationTotal), RegisterLinks: \(Self.registerDurationTotal)")
        }

        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        let sheets = item.entries.compactMap{ entry -> SheetModel? in
            guard !entry.isHexGrid else { return nil }
            return sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
        return sheets
    }

    @MainActor private func sheet(entry: MapEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

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
            case .map:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)
            }
        }

        let inlineEntry = SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), type: .photo, name: "", description: "", entries: [])

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, inlineEntries: [inlineEntry], entries: linkSheets)
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🔄 [Update] Starting update \(itemController.config.module.token) for itemId: \(sheetModel.source.itemId.uuidString), level: \(sheetModel.level)")
        
        let model = itemController.itemOrEmpty(for: sheetModel.source.itemId)

        var changeCount = 0
        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
            if changed { changeCount += 1 }
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
            if changed { changeCount += 1 }
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

        guard !sheetModel.isFolded else {
            let duration = ContinuousClock.now - startTime
            Logger.sheetController.info("✅ [Update] Completed (folded) - Duration: \(duration), Changes: \(changeCount)")
            return
        }
        
        let entryIds = model.entries.map { $0.id }

        // Remove deleted entries
        let removedCount = sheetModel.entries.filter { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }.count
        
        sheetModel.entries.removeAll { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }

        var updatedEntries: [SheetModel] = []
        var updatedCount = 0
        var createdCount = 0
        
        for entry in model.entries {
            if let existingSheetModel = sheetModel.entries.first(where: { $0.source.entryId == entry.id }) {
                unequalSet(lhs: &existingSheetModel.name, rhs: entry.name) { changed in
                    existingSheetModel.hasChanged = changed
                    if changed { updatedCount += 1 }
                }
                unequalSet(lhs: &existingSheetModel.description, rhs: entry.content) { changed in
                    existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
                    if changed { updatedCount += 1 }
                }
                existingSheetModel.entries.forEach { subSheetModel in
                    root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel, isEditor: isEditor)
                }
                updatedEntries.append(existingSheetModel)
            } else {
                createdCount += 1
                updatedEntries.append(sheet(entry: entry, root: root, itemId: model.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor))
            }
        }
        sheetModel.entries = updatedEntries
        
        let duration = ContinuousClock.now - startTime
        Logger.sheetController.info("✅ [Update] Completed - Duration: \(duration), Changed fields: \(changeCount), Removed: \(removedCount), Updated: \(updatedCount), Created: \(createdCount), Total entries: \(updatedEntries.count)")
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
}
