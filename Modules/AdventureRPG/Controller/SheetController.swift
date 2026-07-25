// @copyright André Trettin

import CoreRPG
import Foundation
import os

struct SheetController {
    let itemController: ItemController
}

extension SheetController: SheetControllable {
    @MainActor var linkRegisterController: LinkRegisterController { itemController.itemDataModel.linkRegisterController! }

    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []

        if let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
        }

        // Keep the initial Adventure sheet shallow. Linked sheets are represented by a
        // folded placeholder and materialized by SheetControllable.unfold only when the
        // user opens the link. This prevents closed sub-adventures from recursively
        // constructing their complete sheet hierarchy.
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

    @MainActor func entryNameDescription(entry: AdventureEntryModel, root: RootManager) -> (name: String, description: String) {
        if let adventureId = entry.adventureId {
            let adventure = itemController.reviewAwareItemOrEmpty(root: root, for: adventureId)
            return (adventure.url(linkNumber: 0), adventure.description)
        }
        return (entry.name, entry.content)
    }

    @MainActor private func sheet(entry: AdventureEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)
        let (name, description) = entryNameDescription(entry: entry, root: root)

        var allSheets: [SheetModel] = []
        if let adventureId = entry.adventureId {
            allSheets = [sheet(root: root, itemId: adventureId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)]
        }

        let links = linkRegisterController.linksFrom(source: destination)

        let linkSheets = links.compactMap { link -> SheetModel? in
            guard link.isSheetLink else { return nil }
            let linkDestination = link.destination
            let linkedSheet: SheetModel?
            switch linkDestination.typeId {
            case .adventure:
                if linkDestination.entryId == nil {
                    linkedSheet = sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    linkedSheet = nil
                }
            default:
                linkedSheet = root.rootModel(for: linkDestination.typeId)?.sheetControllable.sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
            }
            linkedSheet?.linkNumber = link.linkNumber
            return linkedSheet
        }
        allSheets.append(contentsOf: linkSheets)

        let entryType: SheetModelType = entry.adventureId != nil ? .group : .item
        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, type: entryType, name: name, description: description, entries: allSheets)
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
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
                let (entryName, entryDescription) = entryNameDescription(entry: entry, root: root)
                unequalSet(lhs: &existingSheetModel.name, rhs: entryName) { changed in
                    existingSheetModel.hasChanged = changed
                    if changed { updatedCount += 1 }
                }
                unequalSet(lhs: &existingSheetModel.description, rhs: entryDescription) { changed in
                    existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
                    if changed { updatedCount += 1 }
                }
                let projectedEntry = sheet(
                    entry: entry,
                    root: root,
                    itemId: model.id,
                    level: sheetModel.level,
                    moduleDepth: 0,
                    isEditor: isEditor
                )
                var unmatchedExisting = existingSheetModel.entries
                let reconciledEntries = projectedEntry.entries.map { projectedChild in
                    guard let existingIndex = unmatchedExisting.firstIndex(where: {
                        $0.source == projectedChild.source &&
                        $0.linkNumber == projectedChild.linkNumber
                    }) else {
                        createdCount += 1
                        existingSheetModel.hasChanged = true
                        return projectedChild
                    }

                    let existingChild = unmatchedExisting.remove(at: existingIndex)
                    existingChild.destination = projectedChild.destination
                    existingChild.linkNumber = projectedChild.linkNumber
                    root.rootModel(for: existingChild.source.typeId)?.sheetControllable.update(
                        root: root,
                        sheetModel: existingChild,
                        isEditor: isEditor
                    )
                    return existingChild
                }
                if !unmatchedExisting.isEmpty {
                    existingSheetModel.hasChanged = true
                }
                existingSheetModel.entries = reconciledEntries
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
