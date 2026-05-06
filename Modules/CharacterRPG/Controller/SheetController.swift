// @copyright André Trettin

import CoreRPG
import Foundation
import os

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
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🚀 [Sheet] Starting sheet creation \(itemController.config.module.token) - itemId: \(itemId.uuidString), level: \(level), moduleDepth: \(moduleDepth)")
        
        let model = itemController.itemOrEmpty(for: itemId)
        var inlineEntries: [SheetModel] = []
        var totalSheetCount = 1 // Count this sheet
        
        if let diceId = model.diceId {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level, isShown: isShown))
            totalSheetCount += 1
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        if isFolded {
            Logger.sheetController.debug("[Sheet] Folded at moduleDepth \(moduleDepth) for itemId: \(itemId.uuidString)")
        }
        
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        
        // Count all nested sheets
        let nestedCount = countSheets(in: entries)
        totalSheetCount += nestedCount
        
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
        
        let duration = ContinuousClock.now - startTime
        Logger.sheetController.info("✅ [Sheet] Completed \(itemController.config.module.token) - Duration: \(duration), Total sheets in subtree: \(totalSheetCount), Direct entries: \(entries.count), Level: \(level), ModuleDepth: \(moduleDepth)")
        
        return sheetModel
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        Logger.sheetController.debug("[Sheet] Creating entries for itemId: \(itemId.uuidString) - Entry count: \(item.entries.count), Level: \(level), ModuleDepth: \(moduleDepth)")
        
        let sheets = item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
        
        return sheets
    }
    
    @MainActor private func sheet(entry: ValueEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let startTime = ContinuousClock.now
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        var allSheets: [SheetModel] = []
        if let subValueId = entry.valueId {
            allSheets = [sheet(root: root, itemId: subValueId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)]
        }
        let links = LinkReplaceController.links(for: entry.content)
        Logger.sheetController.debug("[Sheet] Entry '\(name)' has \(links.count) links - Level: \(level), ModuleDepth: \(moduleDepth)")
        
        let linkSheets = links.compactMap { link -> SheetModel? in
            let linkedModule = link.module.token
            Logger.sheetController.debug("[Sheet] Processing link to module: \(linkedModule), itemId: \(link.itemId.uuidString), hasEntryId: \(link.entryId != nil)")
            
            switch link.module {
            case .value:
                if link.entryId == nil {
                    return sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    Logger.sheetController.debug("[Sheet] Skipping value link with entryId")
                    return nil
                }
            default:
                return root.rootModel(for: link.module)?.sheetControllable.sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: 0, isEditor: isEditor)
            }
        }
        allSheets.append(contentsOf: linkSheets)
        
        let duration = ContinuousClock.now - startTime
        Logger.sheetController.debug("[Sheet] Entry sheet created - Duration: \(duration), Name: '\(name)', Links processed: \(links.count), Sheets from links: \(linkSheets.count)")
        
        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: allSheets)
    }
    
    @MainActor private func createDiceInline(diceId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, isShown: isShown, name: "", description: "", entries: [])
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

        if let diceId = model.diceId {
            let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
            let diceSheetModel = sheetModel.inlineEntries.first ?? createDiceInline(diceId: diceId, itemId: model.id, level: sheetModel.level, isShown: sheetModel.isShown)
            diceSheetModel.source = diceSource
            sheetModel.inlineEntries = [diceSheetModel]
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
