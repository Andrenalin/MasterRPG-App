// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController
}

extension SheetController: SheetControllable {
    @MainActor var linkRegisterController: LinkRegisterController { itemController.linkRegisterController }

    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []

        if let diceId = model.diceId {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level))
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)

        return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        let sheets = item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
        return sheets
    }
    
    @MainActor func sheet(entry: TableEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let name = entry.name
        let description = entry.content
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let links = linkRegisterController.linksFrom(source: destination)

        let linkSheets = links.compactMap { link -> SheetModel? in
            guard link.isSheetLink else { return nil }
            let linkDestination = link.destination
            let linkedSheet: SheetModel?
            switch linkDestination.typeId {
            case .table:
                if linkDestination.entryId == nil {
                    linkedSheet = sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    linkedSheet = nil
                }
            default:
                linkedSheet = SheetLinkGuard.linkedSheet(root: root, module: linkDestination.typeId, itemId: linkDestination.itemId, destination: destination, level: level + 1, isEditor: isEditor)
            }
            linkedSheet?.linkNumber = link.linkNumber
            return linkedSheet
        }

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: name, description: description, entries: linkSheets)
    }
    
    @MainActor func createDiceInline(diceId: UUID, itemId: UUID, level: Int) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let startTime = ContinuousClock.now
        Logger.sheetController.info("🔄 [Update] Starting update \(itemController.config.module.token) for itemId: \(sheetModel.source.itemId.uuidString), level: \(sheetModel.level)")
        
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: sheetModel.source.itemId)

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
            let diceSheetModel = sheetModel.inlineEntries.first ?? createDiceInline(diceId: diceId, itemId: model.id, level: sheetModel.level)
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
        
        // Set/dictionary lookups instead of repeated O(n) .contains/.first(where:)
        // scans — this runs on every sheet refresh. See CODE_AUDIT_Table §7.2.
        let entryIds = Set(model.entries.map { $0.id })

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

        let existingSheetModelsByEntryId = Dictionary(
            sheetModel.entries.compactMap { model in model.source.entryId.map { ($0, model) } },
            uniquingKeysWith: { first, _ in first }
        )

        for entry in model.entries {
            if let existingSheetModel = existingSheetModelsByEntryId[entry.id] {
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
    
}
