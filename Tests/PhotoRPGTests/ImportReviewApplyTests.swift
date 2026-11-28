// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import PhotoRPG

/// CODE_AUDIT_26 §10.2: the import review apply pipeline, away from its view.
@Suite(.serialized)
@MainActor
struct ImportReviewApplyTests {
    private func folderWithChildren() async -> (root: PhotoRootModel, folderId: UUID, keptId: UUID, deletedId: UUID) {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        let folderId = await root.itemController.addNew(type: .folder)
        let keptId = await root.itemController.addNew(type: .item)
        let deletedId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Folder", itemId: folderId, forceSave: false)
        root.editController.reset(name: "Kept", itemId: keptId, forceSave: false)
        root.editController.reset(name: "Deleted", itemId: deletedId, forceSave: false)
        root.editController.addItem(itemId: keptId, parentId: folderId)
        root.editController.addItem(itemId: deletedId, parentId: folderId)
        return (root, folderId, keptId, deletedId)
    }

    @Test("A reviewed deletion goes to the trash, not away")
    func deletionIsTrashed() async throws {
        let (root, folderId, keptId, _) = await folderWithChildren()

        await ImportReviewApplyController.finishReview(root: root, appliedIds: [], deletedIds: [keptId])

        let item = try #require(root.itemController.itemSync(for: keptId, noGame: true))
        #expect(item.displayState == DisplayStateMask.totalHidden.rawValue)
        #expect(root.itemController.itemSync(for: folderId, noGame: true) != nil)
    }

    @Test("The children of a deleted folder that stay move to root; the deleted one stays in the trash")
    func keptChildrenOfDeletedFolderMoveToRoot() async throws {
        let (root, folderId, keptId, deletedId) = await folderWithChildren()

        await ImportReviewApplyController.finishReview(root: root, appliedIds: [], deletedIds: [folderId, deletedId])

        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        #expect(folder.displayState == DisplayStateMask.totalHidden.rawValue)
        let kept = try #require(root.itemController.itemSync(for: keptId, noGame: true))
        #expect(kept.parentId == nil, "the child that stays is not left under the trashed folder")
        #expect(kept.displayState != DisplayStateMask.totalHidden.rawValue)
        let deleted = try #require(root.itemController.itemSync(for: deletedId, noGame: true))
        #expect(deleted.displayState == DisplayStateMask.totalHidden.rawValue)
    }

    @Test("Nothing applied and nothing deleted changes nothing")
    func emptyReviewIsANoOp() async throws {
        let (root, folderId, keptId, _) = await folderWithChildren()

        await ImportReviewApplyController.finishReview(root: root, appliedIds: [], deletedIds: [])

        #expect(root.itemController.itemSync(for: keptId, noGame: true)?.parentId == folderId)
    }

    @Test("Settling review files forgets the writes of a review, also without a root manager")
    func settleClearsTheWrites() async {
        let importModel = ItemDataImportModel()

        await ImportReviewApplyController.settleReviewFiles(importModel: importModel, rootManager: nil)

        #expect(importModel.reviewFileWrites.isEmpty)
    }
}
#endif
