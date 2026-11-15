// @copyright André Trettin

import Foundation
import Observation

/// The review-apply pipeline of an import, moved out of `ImportProgressPanelView` so it can be
/// tested: per item merge onto the changed library item, trash instead of delete, re-parenting
/// of kept folder children, tag restore, folder repair and the settling of the files a review
/// parse wrote. See CODE_AUDIT_26 §10.2.
@MainActor
struct ImportReviewApplyController {
    enum ReviewApplyOutcome {
        case applied, deleted, unchanged
    }

    /// Applies every reviewed item of every module, then finishes each module's review.
    static func applyAll(reviewModel: ImportReviewModel, rootManager: RootManager) async {
        for module in reviewModel.modules {
            guard let root = rootManager.rootModel(for: module.id) else { continue }
            var appliedIds: Set<UUID> = []
            var deletedIds: Set<UUID> = []
            for item in module.reviewItems {
                switch await apply(item: item, root: root) {
                case .applied: appliedIds.insert(item.id)
                case .deleted: deletedIds.insert(item.id)
                case .unchanged: break
                }
            }
            await finishReview(root: root, appliedIds: appliedIds, deletedIds: deletedIds)
        }
    }

    /// After a module's review items were applied: reviewed deletions go to the trash (and are
    /// purged with link, tag and file cleanup at the next launch) instead of being hard-deleted;
    /// the children of a deleted folder that stay move to root; and the folder repair runs over
    /// everything applied. Hard deletes left dangling folder entries and invisible children.
    /// See CODE_AUDIT_Folder §5.9.
    static func finishReview(root: any ItemRootControllable, appliedIds: Set<UUID>, deletedIds: Set<UUID>) async {
        let editController = root.editControllable
        var detachedIds: Set<UUID> = []
        for itemId in deletedIds {
            guard let item = root.itemControllable.itemSync(for: itemId, noGame: true) else { continue }
            let keptChildren = item.isFolder ? item.entries.map(\.childId).filter {
                !deletedIds.contains($0) && root.itemControllable.itemSync(for: $0, noGame: true)?.parentId == itemId
            } : []
            for childId in keptChildren {
                editController.removeItemFromParent(itemId: childId, oneUp: false, moveFiles: true, scope: .library)
                detachedIds.insert(childId)
            }
            editController.markForDeletion(itemId: itemId)
        }
        let repairIds = appliedIds.union(detachedIds)
        guard !repairIds.isEmpty else { return }
        // One pass over the folders for every applied item. See CODE_AUDIT_Folder §7.3.
        editController.repairFolders(itemIds: appliedIds)
        let repair = ConvertController(itemController: root.itemControllable, editController: editController)
        await repair.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: repairIds)
    }

    /// Settles the files a manual-review parse wrote: those an applied item references stay
    /// (and replace its previous file), the rest are removed. See CODE_AUDIT_Folder §5.2, §5.26.
    static func settleReviewFiles(importModel: ItemDataImportModel, rootManager: RootManager?) async {
        let writes = importModel.reviewFileWrites
        importModel.reviewFileWrites = []
        guard let rootManager else { return }
        for write in writes {
            await rootManager.rootModel(for: write.module)?.itemControllable.settleImportedFile(write.write, itemId: write.itemId)
        }
    }


    static func apply(item: ImportReviewItemModel, root: any ItemRootControllable) async -> ReviewApplyOutcome {
        let itemModel = item.itemModel
        if item.isDeletion {
            return itemModel.decision == .imported ? .deleted : .unchanged
        }
        if itemModel.decision == .existing {
            guard itemModel.hasOverrides, itemModel.item.existing != nil else { return .unchanged }
        }
        guard let model = itemModel.materializedItem() as? any Observable & ItemDataAccessible else { return .unchanged }
        // The review was built from the library item as it was at parse time. If it changed
        // while the sheet was open (sync, another window), merge the reviewed result onto the
        // current item instead of overwriting that change. See CODE_AUDIT_Folder §3.17.
        var finalModel: any ModelType = model
        if let parsed = itemModel.item.existing as? any Observable & ItemDataAccessible,
           !root.itemControllable.libraryModel(id: item.id, matches: parsed),
           let merged = root.itemControllable.mergeSync(with: model, forceMerge: true, noGame: true) {
            finalModel = merged
        }
        // A reviewed folder may be a partial copy from a subset export. See CODE_AUDIT_Folder §5.8.
        finalModel = root.itemControllable.keepingLocalFolderChildren(finalModel)
        // An item that leaves the trash takes its tags again: trashing gave their counts back.
        // See CODE_AUDIT_21 §5.30.
        let trashed = DisplayStateMask.totalHidden.rawValue
        if let restored = finalModel as? any ItemDataAccessible, restored.displayState != trashed,
           root.itemControllable.itemSync(for: item.id, noGame: true)?.displayState == trashed {
            root.editControllable.tagController.add(tags: restored.tags, module: root.itemControllable.config.module)
        }
        root.itemControllable.replaceImportedModel(model: finalModel, isInsert: true, forceSave: true)
        return .applied
    }
}
