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
        sheet(root: root, itemId: itemId, destination: destination, level: level, isShown: isShown, moduleDepth: moduleDepth, isEditor: isEditor, showsItemInlines: true, visited: [])
    }

    /// `showsItemInlines` is false for the sub-value of a group entry (`entry.valueId`):
    /// the group entry stands for that value, so the value's own dice and photo are not shown.
    ///
    /// `visited` guards against a cycle in the value/link graph (a plausible
    /// outcome of a merge/import bug, or two devices concurrently editing via
    /// CloudKit sync — the same class of malformed data `EditController`'s
    /// duplication helpers and `GameController`'s entry-path resolution both
    /// already guard against with `RecursionLimits.maxValueLinkDepth`) recursing
    /// indefinitely and crashing with a stack overflow while building the sheet
    /// tree. See CODE_AUDIT_Character §5.1.
    @MainActor private func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool, showsItemInlines: Bool, visited: Set<UUID>) -> SheetModel {
        guard !visited.contains(itemId), visited.count < RecursionLimits.maxValueLinkDepth else {
            return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: true, showHeader: false, name: "", description: "", inlineEntries: [], entries: [])
        }
        let visited = visited.union([itemId])

        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        var inlineEntries: [SheetModel] = []

        if showsItemInlines, let diceId = model.diceId {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level, isShown: isShown))
        }

        if showsItemInlines, let photoId = model.photoId {
            inlineEntries.append(createPhotoInline(photoId: photoId, itemId: itemId, level: level, isShown: isShown))
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor, visited: visited)

        let showHeader = model.displayState == DisplayStateMask.fullVisible.rawValue
        return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, showHeader: showHeader, name: model.name, description: model.description, inlineEntries: inlineEntries, entries: entries)
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor, visited: [])
    }

    @MainActor private func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool, visited: Set<UUID>) -> [SheetModel] {
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        let sheets = item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor, visited: visited)
        }
        return sheets
    }

    /// - Parameter isShallow: the group sub-value is projected folded, without its own entries.
    ///   `update` uses it for an entry that already has a sheet: the matched children are updated
    ///   (and so projected) by their own `update`, so building their subtree here as well made
    ///   every nesting level rebuild everything below it. See CODE_AUDIT_26 §7.16.
    @MainActor private func sheet(entry: ValueEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool, isShallow: Bool = false) -> SheetModel {
        sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor, visited: [], isShallow: isShallow)
    }

    @MainActor private func sheet(entry: ValueEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool, visited: Set<UUID>, isShallow: Bool = false) -> SheetModel {
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)
        let (name, description) = entryNameDescription(entry: entry, root: root)

        var inlineEntries: [SheetModel] = []
        // A group value (an entry that holds a sub-value) shows no dice of its own.
        if let diceId = entry.diceId, entry.valueId == nil, entry.supportsDice {
            inlineEntries.append(createDiceInline(diceId: diceId, itemId: itemId, level: level, isShown: true, destination: destination))
        }

        var allSheets: [SheetModel] = []
        if let subValueId = entry.valueId {
            allSheets = [sheet(root: root, itemId: subValueId, destination: destination, level: level + 1, isShown: false, moduleDepth: isShallow ? 1 : 0, isEditor: isEditor, showsItemInlines: false, visited: visited)]
        }

        let links = linkRegisterController.linksFrom(source: destination)

        let linkSheets = links.compactMap { link -> SheetModel? in
            guard link.isSheetLink else { return nil }
            let linkDestination = link.destination
            let linkedSheet: SheetModel?
            switch linkDestination.typeId {
            case .value:
                if linkDestination.entryId == nil {
                    linkedSheet = sheet(root: root, itemId: linkDestination.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor, showsItemInlines: true, visited: visited)
                } else {
                    linkedSheet = nil
                }
            default:
                linkedSheet = SheetLinkGuard.linkedSheet(root: root, module: linkDestination.typeId, itemId: linkDestination.itemId, destination: destination, level: level + 1, isEditor: isEditor)
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
    
    /// Shared "dice inline sheet" construction — previously hand-rolled
    /// verbatim at three call sites, which had already drifted once (one
    /// call site omitted `isShown`). See CODE_AUDIT_Character §9.11.
    @MainActor private func createDiceInline(diceId: UUID, itemId: UUID, level: Int, isShown: Bool, destination: ItemRowModel? = nil) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: diceId, typeId: .dice), destination: destination ?? ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .dice, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor private func createPhotoInline(photoId: UUID, itemId: UUID, level: Int, isShown: Bool) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: photoId, typeId: .photo), destination: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .photo, isShown: isShown, name: "", description: "", entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        update(root: root, sheetModel: sheetModel, isEditor: isEditor, showsItemInlines: true)
    }

    @MainActor private func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool, showsItemInlines: Bool) {
        let startTime = ContinuousClock.now
        Logger.sheetController.debug("🔄 [Update] Starting update \(itemController.config.module.token) for itemId: \(sheetModel.source.itemId.uuidString), level: \(sheetModel.level)")
        
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: sheetModel.source.itemId)

        var changeCount = 0
        var updatedInlineEntries: [SheetModel] = []

        if showsItemInlines, let diceId = item.diceId {
            let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
            // Reuse existing if found, otherwise create new
            let diceSheetModel = sheetModel.inlineEntries.first(where: { $0.sheetType == .dice }) ?? createDiceInline(diceId: diceId, itemId: item.id, level: sheetModel.level, isShown: sheetModel.isShown)
            diceSheetModel.source = diceSource
            updatedInlineEntries.append(diceSheetModel)
        }

        if showsItemInlines, let photoId = item.photoId {
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
        Logger.sheetController.debug("✅ [Update] Completed - Duration: \(duration), Total entries: \(item.entries.count)")
    }
    
    @MainActor private func updateEntries(item: ValueModel, root: RootManager, in sheetModel: SheetModel, isEditor: Bool) {
        let entryIds = Set(item.entries.map(\.id))
        
        sheetModel.entries.removeAll { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }
        var existingSheetModels: [UUID: SheetModel] = [:]
        for existing in sheetModel.entries {
            if let entryId = existing.source.entryId, existingSheetModels[entryId] == nil {
                existingSheetModels[entryId] = existing
            }
        }
        
        var updatedEntries: [SheetModel] = []
        
        for entry in item.entries {
            let updated = update(entry: entry, item: item, root: root, in: sheetModel, existing: existingSheetModels[entry.id], isEditor: isEditor)
            updatedEntries.append(updated)
        }
        sheetModel.entries = updatedEntries
    }
    
    @MainActor private func update(entry: ValueEntryModel, item: ValueModel, root: RootManager, in sheetModel: SheetModel, existing: SheetModel?, isEditor: Bool) -> SheetModel {
        guard let existingSheetModel = existing else {
            return sheet(entry: entry, root: root, itemId: item.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor)
        }

        // Re-project the entry from scratch so a newly attached/removed sub-value or link
        // (e.g. converting the entry to a group) is reflected in sheetType and entries,
        // not just in name/description.
        let projectedEntry = sheet(entry: entry, root: root, itemId: item.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor, isShallow: true)

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
        if let diceId = entry.diceId, entry.valueId == nil, entry.supportsDice {
            let destination = ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemController.config.module)
            let diceSource = ItemRowModel(itemId: diceId, typeId: .dice)
            let diceSheetModel = existingSheetModel.inlineEntries.first(where: { $0.sheetType == .dice }) ?? createDiceInline(diceId: diceId, itemId: item.id, level: sheetModel.level, isShown: true, destination: destination)
            diceSheetModel.source = diceSource
            existingSheetModel.inlineEntries = [diceSheetModel]
        } else {
            existingSheetModel.inlineEntries = []
        }

        var unmatchedExisting = existingSheetModel.entries
        let reconciledEntries = projectedEntry.entries.enumerated().map { offset, projectedChild -> SheetModel in
            guard let existingIndex = unmatchedExisting.firstIndex(where: {
                $0.source == projectedChild.source && $0.linkNumber == projectedChild.linkNumber
            }) else {
                existingSheetModel.hasChanged = true
                // A new sub-value has no sheet to update, and the shallow projection left it folded.
                if entry.valueId != nil, offset == 0 {
                    return sheet(root: root, itemId: projectedChild.source.itemId, destination: projectedChild.destination, level: projectedChild.level, isShown: false, moduleDepth: 0, isEditor: isEditor, showsItemInlines: false, visited: [])
                }
                return projectedChild
            }

            let existingChild = unmatchedExisting.remove(at: existingIndex)
            existingChild.destination = projectedChild.destination
            existingChild.linkNumber = projectedChild.linkNumber
            // The first child of a group entry is its sub-value, which hides its own dice and photo.
            if entry.valueId != nil, offset == 0 {
                update(root: root, sheetModel: existingChild, isEditor: isEditor, showsItemInlines: false)
            } else {
                root.rootModel(for: existingChild.source.typeId)?.sheetControllable.update(root: root, sheetModel: existingChild, isEditor: isEditor)
            }
            return existingChild
        }
        if !unmatchedExisting.isEmpty {
            existingSheetModel.hasChanged = true
        }
        existingSheetModel.entries = reconciledEntries

        return existingSheetModel
    }
}
