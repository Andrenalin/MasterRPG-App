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
        if model.hasAudio {
            inlineEntries.append(
                createAudioInline(itemId: itemId, level: level, isShown: isShown, name: model.name, description: model.description)
                )
        }

        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        let sheetModel = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, canAdd: false, showHeader: false, name: model.name, description: model.hasAudio ? "" : model.description, inlineEntries: inlineEntries, entries: entries)
        return sheetModel
    }

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        return item.entries.map { entry in
            sheetEntry(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
    }

    @MainActor private func sheetEntry(entry: AudioEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let track = itemController.reviewAwareItemOrEmpty(root: root, for: entry.audioId)
        var name = track.name
        let description = track.description
        if track.specialCategory {
            name = track.url(linkNumber: 0)
        }

        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)

        let links = LinkReplaceController.links(for: description)
        let linkSheets = links.compactMap { link -> SheetModel? in
            guard link.command == nil else { return nil }
            let linkedSheet: SheetModel?
            switch link.module {
            case .audio:
                if link.entryId == nil {
                    linkedSheet = sheet(root: root, itemId: link.itemId, destination: destination, level: level + 1, isShown: false, moduleDepth: moduleDepth + 1, isEditor: isEditor)
                } else {
                    linkedSheet = nil
                }
            default:
                linkedSheet = SheetLinkGuard.linkedSheet(root: root, module: link.module, itemId: link.itemId, destination: destination, level: level + 1, isEditor: isEditor)
            }
            linkedSheet?.linkNumber = link.linkNumber
            return linkedSheet
        }

        return SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), destination: destination, level: level, type: .audio, name: name, description: description, entries: linkSheets)
    }

    @MainActor private func createAudioInline(itemId: UUID, level: Int, isShown: Bool, name: String, description: String) -> SheetModel {
        SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), level: level, type: .audio, isShown: isShown, name: name, description: description, entries: [])
    }

    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: sheetModel.source.itemId)

        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
        }

        // Update inline entries (audio)
        if model.hasAudio {
            let audioSource = ItemRowModel(itemId: sheetModel.source.itemId, typeId: itemController.config.module)
            let audioSheetModel = sheetModel.inlineEntries.first ?? createAudioInline(itemId: model.id, level: sheetModel.level, isShown: sheetModel.isShown, name: model.name, description: model.description)
            audioSheetModel.source = audioSource
            unequalSet(lhs: &audioSheetModel.name, rhs: model.name) { _ in }
            unequalSet(lhs: &audioSheetModel.description, rhs: model.description) { _ in }
            sheetModel.inlineEntries = [audioSheetModel]
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
        for entry in model.entries {
            if let existingSheetModel = sheetModel.entries.first(where: { $0.source.entryId == entry.id }) {
                let track = itemController.reviewAwareItemOrEmpty(root: root, for: entry.audioId)
                var name = track.name
                let description = track.description
                if track.specialCategory {
                    name = track.url(linkNumber: 0)
                }

                unequalSet(lhs: &existingSheetModel.name, rhs: name) { changed in
                    existingSheetModel.hasChanged = changed
                }
                unequalSet(lhs: &existingSheetModel.description, rhs: description) { changed in
                    existingSheetModel.hasChanged = existingSheetModel.hasChanged || changed
                }
                existingSheetModel.entries.forEach { subSheetModel in
                    root.rootModel(for: subSheetModel.source.typeId)?.sheetControllable.update(root: root, sheetModel: subSheetModel, isEditor: isEditor)
                }
                updatedEntries.append(existingSheetModel)
            } else {
                updatedEntries.append(sheetEntry(entry: entry, root: root, itemId: model.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
