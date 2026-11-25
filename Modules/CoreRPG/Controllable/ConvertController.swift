// @copyright André Trettin

import Foundation

public struct ConvertController: Sendable {
    public init(itemController: any ItemControllable, editController: any EditControllable) {
        self.itemController = itemController
        self.editController = editController
    }
    
    let itemController: any ItemControllable
    let editController: any EditControllable
    
    @MainActor public func repairHiddenAndFolders(reportModel: ValidateRepairModel) async {
        await repairItems(reportModel: reportModel, only: nil)
    }

    @MainActor public func repairImportedItems(reportModel: ValidateRepairModel, importedIds: Set<UUID>) async {
        guard !importedIds.isEmpty else { return }
        await repairItems(reportModel: reportModel, only: importedIds)
    }

    /// Repairs either the whole library (`repairIds == nil`, from `repairHiddenAndFolders`)
    /// or just the ids from one import batch. The targeted path iterates `repairIds`
    /// directly instead of scanning every item in the module and filtering by
    /// membership — this runs after every non-manual import, including every
    /// live game-networking sync, so scanning the full item list on each call would
    /// scale with total library size instead of with the (usually tiny) import batch.
    /// See CODE_AUDIT_Import §7.1.
    @MainActor private func repairItems(reportModel: ValidateRepairModel, only repairIds: Set<UUID>?) async {
        let itemIds = repairIds.map(Array.init) ?? itemController.itemDataModel.items
        for itemId in itemIds {
            guard !Task.isCancelled else { return }
            guard let item = itemController.itemSync(for: itemId), !item.isHidden else { continue }

            // Increment progress and yield so @Observable notifies SwiftUI before continuing.
            // Without the yield every update queues up and SwiftUI renders them all at once at the end.
            reportModel.increaseCurrent()
            await Task.yield()

            if item.isFolder {
                editController.cleanFolder(itemId: itemId)
            }

            let repairFolder = itemController.config.module != .value
            if repairFolder, let parentId = item.parentId {
                if let parent = itemController.itemSync(for: parentId) {
                    let isOrphaned = !parent.entries.contains(where: { $0.childId == item.id })
                    if isOrphaned {
                        editController.removeItemFromParent(itemId: item.id, oneUp: false, moveFiles: false)
                    }
                } else {
                    editController.removeItemFromParent(itemId: item.id, oneUp: false, moveFiles: false)
                }
            }

            if editController.isOrphanedHidden(itemId: itemId) {
                editController.willRepairOrphan(itemId: itemId)
                editController.reset(hidden: false, itemId: itemId)
            }

            if ImportItemRepair.shouldNormalizeLegacyCategory(item.category) {
                let category = item.category
                editController.reset(category: .entry, itemId: itemId)
                editController.reset(tags: ImportItemRepair.normalizedTags(legacyCategory: category, tags: item.tags), itemId: itemId)
            }

            // Earlier Validate runs tagged the legacy `.item` category as "Item" / "Gegenstand".
            if let current = itemController.itemSync(for: itemId) {
                let cleanedTags = ImportItemRepair.removingItemCategoryTags(from: current.tags)
                if cleanedTags != current.tags {
                    editController.reset(tags: cleanedTags, itemId: itemId)
                }
            }

            if itemController.config.module == .photo && item.category == .entry {
                for entry in item.entries {
                    editController.removeGroup(itemId: itemId, childId: entry.childId)
                }
            }

            if let repairedItem = itemController.itemSync(for: itemId) {
                resetLinkRegister(for: repairedItem)
            }
        }
    }

    @MainActor private func resetLinkRegister(for item: any ItemLinkRegistrable) {
        let register = editController.linkRegisterController
        // The per-source index, not a scan of every destination's links per repaired item.
        // See CODE_AUDIT_Folder §7.3.
        register.deregister(links: register.model.sourceItems[item.id] ?? [])
        register.register(links: item.linkRegisterModels)
    }
}
