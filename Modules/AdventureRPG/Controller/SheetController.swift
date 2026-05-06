// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController
    
    // Track statistics for sheet creation
    private static let sheetCountLock = OSAllocatedUnfairLock(initialState: 0)
    private static let maxDepthLock = OSAllocatedUnfairLock(initialState: 0)
    
    @MainActor func sheet(for itemId: UUID, level: Int = 0) -> SheetFirstModel {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🚀 [SheetFirst] Starting sheet creation for \(itemController.config.module.token) itemId: \(itemId.uuidString), level: \(level)")
        
        let model = itemController.itemOrEmpty(for: itemId)
        var entries: [SheetFirstModel] = []
        var sheetCount = 1 // Count this sheet
        
        if let photoId = model.photoId {
            entries.append(SheetFirstModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, name: "", description: "", entries: []))
            sheetCount += 1
        }
        
        let subEntries = sheetEntries(for: itemId, level: level + 1)
        entries.append(contentsOf: subEntries)
        sheetCount += subEntries.count
        
        let sheetModel = SheetFirstModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, name: model.name, description: model.description, entries: entries)
        
        let duration = ContinuousClock.now - startTime
        Logger.sheetController.info("✅ [SheetFirst] Completed sheet creation \(itemController.config.module.token) - Duration: \(duration), Sheets created: \(sheetCount), Max depth: \(level + 1)")
        
        return sheetModel
    }

    @MainActor func sheetEntries(for itemId: UUID, level: Int) -> [SheetFirstModel] {
        guard level < 4 else {
            Logger.sheetController.debug("[SheetFirst] Max depth reached at level \(level) for itemId: \(itemId.uuidString)")
            return []
        }
        
        let value = itemController.itemOrEmpty(for: itemId)
        let entries = value.entries.map { entry in
            let name = entry.name
            let description = entry.content
            return SheetFirstModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: [])
        }
        
        Logger.sheetController.debug("[SheetFirst] Created \(entries.count) entries at level \(level) for itemId: \(itemId.uuidString)")
        return entries
    }
}

extension SheetController: SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🚀 [Sheet] Starting sheet creation \(itemController.config.module.token) - itemId: \(itemId.uuidString), level: \(level), moduleDepth: \(moduleDepth), module: \(self.itemController.config.module.rawValue)")
        
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        var totalSheetCount = 1 // Count this sheet
        
        if let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
            totalSheetCount += 1
        }

        let isFolded = moduleDepth >= 3
        if isFolded {
            Logger.sheetController.debug("[Sheet] Folded at moduleDepth \(moduleDepth) for itemId: \(itemId.uuidString)")
        }
        
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        
        // Count all nested sheets
        let nestedCount = countSheets(in: entries)
        totalSheetCount += nestedCount
        
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        
        let duration = ContinuousClock.now - startTime
        Logger.sheetController.info("✅ [Sheet] Completed \(itemController.config.module.token) - Duration: \(duration), Total sheets in subtree: \(totalSheetCount), Direct entries: \(entries.count), Level: \(level), ModuleDepth: \(moduleDepth)")
        
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: 0)
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        Logger.sheetController.debug("[Sheet] Creating entries for itemId: \(itemId.uuidString) - Entry count: \(item.entries.count), Level: \(level), ModuleDepth: \(moduleDepth)")
        
        let sheets = item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth)
        }
        
        return sheets
    }

    @MainActor private func sheet(entry: AdventureEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int) -> SheetModel {
        let startTime = ContinuousClock.now
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let links = LinkReplaceController.links(for: entry.content)
        Logger.sheetController.debug("[Sheet] Entry '\(name)' has \(links.count) links - Level: \(level), ModuleDepth: \(moduleDepth)")
        
        let linkSheets = links.compactMap { link -> SheetModel? in
            let linkedModule = link.module.rawValue
            Logger.sheetController.debug("[Sheet] Processing link to module: \(linkedModule), itemId: \(link.itemId.uuidString), hasEntryId: \(link.entryId != nil)")
            
            switch link.module {
            case .adventure:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1)
                } else {
                    Logger.sheetController.debug("[Sheet] Skipping adventure link with entryId")
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0)
            }
        }

        let duration = ContinuousClock.now - startTime
        Logger.sheetController.debug("[Sheet] Entry sheet created - Duration: \(duration), Name: '\(name)', Links processed: \(links.count), Sheets from links: \(linkSheets.count)")
        
        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: linkSheets)
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel) {
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
                    root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel)
                }
                updatedEntries.append(existingSheetModel)
            } else {
                createdCount += 1
                updatedEntries.append(sheet(entry: entry, root: root, itemId: model.id, level: sheetModel.level, moduleDepth: 0))
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
