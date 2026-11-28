// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG
@testable import SpaceRPG

/// CODE_AUDIT_Folder §5: folder and collection operations, with SpaceRPG as the host module
/// (its entries have their own ids, separate from the member they point at).
@MainActor
struct FolderOperationAuditTests {
    private let trashed = DisplayStateMask.totalHidden.rawValue

    private func makeRoot() async -> SpaceRootModel {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    private func addItem(_ root: SpaceRootModel, name: String, type: ItemListCategory = .item) async -> UUID {
        let id = await root.itemController.addNew(type: type)
        root.editController.reset(name: name, itemId: id, forceSave: false)
        return id
    }

    private func childIds(_ root: SpaceRootModel, of itemId: UUID) -> [UUID] {
        root.itemController.itemSync(for: itemId)?.entries.map(\.childId) ?? []
    }

    // MARK: - §5.1 / §5.4 delete and restore

    @Test("A child the delete panel keeps survives the purge of its trashed folder (§5.1)")
    func keptChildSurvivesFolderPurge() async {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let keptId = await addItem(root, name: "Kept")
        let removedId = await addItem(root, name: "Removed")
        sut.addItem(itemId: keptId, parentId: folderId)
        sut.addItem(itemId: removedId, parentId: folderId)

        // Delete the folder; the panel keeps the linked child and confirms the rest.
        let candidates = sut.collectionItemsForRemoval(for: [ItemRowModel(itemId: folderId, typeId: .space)])
        sut.confirmRemoval(of: candidates, keeping: [ItemRowModel(itemId: keptId, typeId: .space)], forceSave: false)
        #expect(!childIds(root, of: folderId).contains(keptId), "the kept child leaves the trashed folder")

        // The launch-time purge of the trashed folder.
        await sut.delete(itemId: folderId)

        let kept = root.itemController.itemSync(for: keptId)
        #expect(kept != nil, "the kept child must not be purged with the folder")
        #expect(kept?.parentId == nil)
        #expect(kept?.displayState == DisplayStateMask.fullVisible.rawValue)
        #expect(root.itemController.itemSync(for: removedId) == nil)
        #expect(root.itemController.itemSync(for: folderId) == nil)
    }

    @Test("Purging a folder skips a stale entry that points at an item living elsewhere (§5.1)")
    func folderPurgeSkipsChildrenOfOtherFolders() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let staleFolderId = await addItem(root, name: "Old", type: .folder)
        let currentFolderId = await addItem(root, name: "New", type: .folder)
        let itemId = await addItem(root, name: "Item")
        sut.addItem(itemId: itemId, parentId: currentFolderId)
        // A stale entry, as an import or sync merge can leave behind.
        let staleFolder = try #require(sut.editModel(for: staleFolderId))
        staleFolder.entries.append(SpaceEntryModel.newChild(id: itemId))
        sut.save(updated: staleFolder, message: "stale", forceSave: false)

        sut.markForDeletion(itemId: staleFolderId, forceSave: false)
        await sut.delete(itemId: staleFolderId)

        #expect(root.itemController.itemSync(for: itemId)?.parentId == currentFolderId)
    }

    @Test("Cancelling a folder delete keeps its children in the folder (§5.4)")
    func cancelKeepsFolderStructure() async {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let subfolderId = await addItem(root, name: "Sub", type: .folder)
        let childId = await addItem(root, name: "Child")
        let grandchildId = await addItem(root, name: "Grandchild")
        sut.addItem(itemId: subfolderId, parentId: folderId)
        sut.addItem(itemId: childId, parentId: folderId)
        sut.addItem(itemId: grandchildId, parentId: subfolderId)

        let removing = sut.collectionItemsForRemoval(for: [ItemRowModel(itemId: folderId, typeId: .space)])
        sut.confirmRemoval(of: removing, keeping: [], forceSave: false)
        sut.restore(itemIds: removing.map(\.itemId), forceSave: false)

        #expect(root.itemController.itemSync(for: childId)?.parentId == folderId)
        #expect(root.itemController.itemSync(for: subfolderId)?.parentId == folderId)
        #expect(root.itemController.itemSync(for: grandchildId)?.parentId == subfolderId)
        #expect(Set(childIds(root, of: folderId)) == [subfolderId, childId])
        for id in [folderId, subfolderId, childId, grandchildId] {
            #expect(root.itemController.itemSync(for: id)?.displayState == DisplayStateMask.fullVisible.rawValue)
        }
    }

    @Test("A folder and its child selected together are marked once (§5.30)")
    func removalListHasNoDuplicates() async {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let childId = await addItem(root, name: "Child")
        sut.addItem(itemId: childId, parentId: folderId)

        let removing = sut.collectionItemsForRemoval(for: [
            ItemRowModel(itemId: folderId, typeId: .space),
            ItemRowModel(itemId: childId, typeId: .space)
        ])

        let removedIds = removing.map(\.itemId)
        #expect(removedIds.count == 2)
        #expect(Set(removedIds) == [folderId, childId])
    }

    @Test("Opening the delete panel trashes nothing; only Remove does (CODE_AUDIT_21 §5.29)")
    func removalIsTrashedOnConfirmationOnly() async {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let childId = await addItem(root, name: "Child")
        sut.addItem(itemId: childId, parentId: folderId)

        // What Delete does before the panel opens. An app terminated now, or a launch cleanup
        // running under the open panel, finds nothing in the trash.
        let candidates = sut.collectionItemsForRemoval(for: [ItemRowModel(itemId: folderId, typeId: .space)])
        #expect(Set(candidates.map(\.itemId)) == [folderId, childId])
        for id in [folderId, childId] {
            #expect(root.itemController.itemSync(for: id)?.displayState == DisplayStateMask.fullVisible.rawValue)
        }

        sut.confirmRemoval(of: candidates, keeping: [], forceSave: false)
        for id in [folderId, childId] {
            #expect(root.itemController.itemSync(for: id)?.displayState == DisplayStateMask.totalHidden.rawValue)
        }
    }

    // MARK: - §5.6 repair

    @Test("repairFolder removes a stale entry even when another folder is checked first (§5.6)")
    func repairFolderChecksEveryFolder() async throws {
        let root = await makeRoot()
        let sut = root.editController
        _ = await addItem(root, name: "A Empty", type: .folder)
        let staleFolderId = await addItem(root, name: "B Stale", type: .folder)
        let parentId = await addItem(root, name: "C Parent", type: .folder)
        let itemId = await addItem(root, name: "Item")
        sut.addItem(itemId: itemId, parentId: parentId)
        let staleFolder = try #require(sut.editModel(for: staleFolderId))
        staleFolder.entries.append(SpaceEntryModel.newChild(id: itemId))
        sut.save(updated: staleFolder, message: "stale", forceSave: false)

        sut.repairFolder(itemId: itemId, forceSave: false)

        #expect(!childIds(root, of: staleFolderId).contains(itemId))
        #expect(childIds(root, of: parentId).contains(itemId))
    }

    @Test("repairFolder cleans every folder when the item moved to root (§5.6)")
    func repairFolderHandlesMoveToRoot() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let itemId = await addItem(root, name: "Item")
        let folder = try #require(sut.editModel(for: folderId))
        folder.entries.append(SpaceEntryModel.newChild(id: itemId))
        sut.save(updated: folder, message: "stale", forceSave: false)

        sut.repairFolder(itemId: itemId, forceSave: false)

        #expect(childIds(root, of: folderId).isEmpty)
    }

    @Test("Removing an item from a folder that only holds a stale entry removes that entry (§5.30)")
    func removeStaleEntryFromOtherFolder() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let staleFolderId = await addItem(root, name: "Old", type: .folder)
        let currentFolderId = await addItem(root, name: "New", type: .folder)
        let itemId = await addItem(root, name: "Item")
        sut.addItem(itemId: itemId, parentId: currentFolderId)
        let staleFolder = try #require(sut.editModel(for: staleFolderId))
        staleFolder.entries.append(SpaceEntryModel.newChild(id: itemId))
        sut.save(updated: staleFolder, message: "stale", forceSave: false)

        sut.remove(itemId: itemId, parentId: staleFolderId, oneUp: false)

        #expect(!childIds(root, of: staleFolderId).contains(itemId))
        #expect(root.itemController.itemSync(for: itemId)?.parentId == currentFolderId)
    }

    // MARK: - §5.15 / §5.16 / §5.17 collections

    @Test("Members are reordered and removed by row id, also when a member is listed twice (§5.15, §5.17)")
    func collectionMembersByRowId() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let collectionId = await addItem(root, name: "Set", type: root.itemController.collectionCategory)
        let firstId = await addItem(root, name: "First")
        let secondId = await addItem(root, name: "Second")
        sut.addItem(itemId: firstId, parentId: collectionId)
        sut.addItem(itemId: secondId, parentId: collectionId)
        // `addItem` rejects a second add (CODE_AUDIT_28 §5.2); a sync or an old file can still
        // bring the same member in twice, which is what this test is about.
        let withDuplicate = try #require(root.itemController.itemSync(for: collectionId)).copy()
        withDuplicate.entries.append(.newChild(id: firstId))
        root.itemController.replace(model: withDuplicate, isInsert: false)
        #expect(childIds(root, of: collectionId) == [firstId, secondId, firstId])

        let collection = try #require(root.itemController.itemSync(for: collectionId))
        let rowIds = collection.memberRowIds()
        #expect(Set(rowIds).count == 3, "every row has its own id")

        sut.moveMember(rowId: rowIds[1], to: rowIds[0], in: collectionId)
        #expect(childIds(root, of: collectionId) == [secondId, firstId, firstId])

        let movedRowIds = try #require(root.itemController.itemSync(for: collectionId)).memberRowIds()
        sut.removeMembers(rowIds: [movedRowIds[2]], from: collectionId)
        #expect(childIds(root, of: collectionId) == [secondId, firstId])
    }

    @Test("A duplicate of a collection member is visible and joins the collection (§5.16)")
    func duplicateOfCollectionMemberStaysVisible() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let collectionId = await addItem(root, name: "Set", type: root.itemController.collectionCategory)
        let memberId = await addItem(root, name: "Member")
        sut.addItem(itemId: memberId, parentId: collectionId)
        let before = Set(root.itemController.itemDataModel.items)

        await sut.duplicate(item: try #require(root.itemController.itemSync(for: memberId)))

        let copyId = try #require(Set(root.itemController.itemDataModel.items).subtracting(before).first)
        #expect(root.itemController.itemSync(for: copyId)?.displayState == DisplayStateMask.fullVisible.rawValue)
        #expect(root.itemController.itemSync(for: memberId)?.displayState == DisplayStateMask.fullVisible.rawValue)
        #expect(childIds(root, of: collectionId).contains(copyId))
    }

    @Test("Adding a member to a collection adds a reference without hiding it (§5.16)")
    func addToCollectionDoesNotHide() async {
        let root = await makeRoot()
        let collectionId = await addItem(root, name: "Set", type: root.itemController.collectionCategory)
        let memberId = await addItem(root, name: "Member")

        root.editController.addItem(itemId: memberId, parentId: collectionId)

        #expect(childIds(root, of: collectionId) == [memberId])
        #expect(root.itemController.itemSync(for: memberId)?.displayState == DisplayStateMask.fullVisible.rawValue)
    }

    @Test("A duplicated folder's children belong to the copy (§5.5)")
    func duplicatedFolderChildrenBelongToCopy() async throws {
        let root = await makeRoot()
        let sut = root.editController
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let childId = await addItem(root, name: "Child")
        sut.addItem(itemId: childId, parentId: folderId)
        let before = Set(root.itemController.itemDataModel.items)

        await sut.duplicate(item: try #require(root.itemController.itemSync(for: folderId)))

        let newIds = Set(root.itemController.itemDataModel.items).subtracting(before)
        let copyFolderId = try #require(newIds.first { root.itemController.itemSync(for: $0)?.isFolder == true })
        let copyChildId = try #require(newIds.first { $0 != copyFolderId })
        #expect(root.itemController.itemSync(for: copyChildId)?.parentId == copyFolderId)
        #expect(childIds(root, of: copyFolderId) == [copyChildId])
        #expect(root.itemController.itemSync(for: childId)?.parentId == folderId)
    }

    // MARK: - §5.19 tags

    @Test("Removing a tag lowers its count (§5.19)")
    func removedTagLosesItsCount() async {
        let root = await makeRoot()
        let sut = root.editController
        let tag = "tag-\(UUID().uuidString)"
        let itemId = await addItem(root, name: "Tagged")

        sut.reset(tags: [tag], itemId: itemId, forceSave: false)
        #expect(sut.tagController.model.tags[.space]?[tag]?.count == 1)
        sut.reset(tags: [], itemId: itemId, forceSave: false)

        #expect(sut.tagController.model.tags[.space]?[tag] == nil)
    }

    @Test("Marking an item for deletion twice gives its tags back once (§5.19)")
    func markForDeletionIsIdempotent() async {
        let root = await makeRoot()
        let sut = root.editController
        let tag = "tag-\(UUID().uuidString)"
        let firstId = await addItem(root, name: "First")
        let secondId = await addItem(root, name: "Second")
        sut.reset(tags: [tag], itemId: firstId, forceSave: false)
        sut.reset(tags: [tag], itemId: secondId, forceSave: false)
        #expect(sut.tagController.model.tags[.space]?[tag]?.count == 2)

        sut.markForDeletion(itemId: firstId, forceSave: false)
        sut.markForDeletion(itemId: firstId, forceSave: false)

        #expect(sut.tagController.model.tags[.space]?[tag]?.count == 1)
        #expect(root.itemController.itemSync(for: firstId)?.displayState == trashed)
    }
}
