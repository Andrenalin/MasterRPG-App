// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG
@testable import SpaceRPG

/// CODE_AUDIT_Folder §7.3 and §7.4: batched folder repair and the Move/Add target check, with
/// SpaceRPG as the host module.
@MainActor
struct FolderPerformanceAuditTests {
    private func makeRoot() async -> SpaceRootModel {
        let root = SpaceRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    private func addItem(_ root: SpaceRootModel, name: String, type: ItemListCategory = .item) async -> UUID {
        let id = await root.itemController.addNew(type: type)
        root.editController.reset(name: name, itemId: id)
        return id
    }

    private func childIds(_ root: SpaceRootModel, of itemId: UUID) -> [UUID] {
        root.itemController.itemSync(for: itemId)?.entries.map(\.childId) ?? []
    }

    private func appendStaleEntry(_ root: SpaceRootModel, folderId: UUID, childId: UUID) throws {
        let folder = try #require(root.editController.editModel(for: folderId))
        folder.entries.append(SpaceEntryModel.newChild(id: childId))
        root.editController.save(updated: folder, message: "stale")
    }

    @Test("One batch repair removes every stale folder entry and keeps the real ones (§7.3)")
    func batchRepairRemovesStaleEntries() async throws {
        let root = await makeRoot()
        let staleFolderId = await addItem(root, name: "Old", type: .folder)
        let currentFolderId = await addItem(root, name: "New", type: .folder)
        let movedId = await addItem(root, name: "Moved")
        let rootItemId = await addItem(root, name: "At root")
        let untouchedId = await addItem(root, name: "Not imported")
        root.editController.addItem(itemId: movedId, parentId: currentFolderId)
        root.editController.addItem(itemId: untouchedId, parentId: currentFolderId)
        try appendStaleEntry(root, folderId: staleFolderId, childId: movedId)
        try appendStaleEntry(root, folderId: staleFolderId, childId: rootItemId)
        try appendStaleEntry(root, folderId: staleFolderId, childId: untouchedId)

        root.editController.repairFolders(itemIds: [movedId, rootItemId])

        #expect(childIds(root, of: staleFolderId) == [untouchedId], "only the batch's items are repaired")
        #expect(Set(childIds(root, of: currentFolderId)) == [movedId, untouchedId])
    }

    @Test("The single-item repair still works through the batch (§7.3)")
    func singleRepairUsesBatch() async throws {
        let root = await makeRoot()
        let staleFolderId = await addItem(root, name: "Old", type: .folder)
        let itemId = await addItem(root, name: "Item")
        try appendStaleEntry(root, folderId: staleFolderId, childId: itemId)

        root.editController.repairFolder(itemId: itemId)

        #expect(childIds(root, of: staleFolderId).isEmpty)
    }

    @Test("A folder of the batch lists exactly the children whose parent it is (§9.8)")
    func batchFolderFollowsItsChildren() async throws {
        let root = await makeRoot()
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let otherFolderId = await addItem(root, name: "Other", type: .folder)
        let keptId = await addItem(root, name: "Kept")
        let movedId = await addItem(root, name: "Moved")
        let unlistedId = await addItem(root, name: "Unlisted")
        root.editController.addItem(itemId: keptId, parentId: folderId)
        root.editController.addItem(itemId: movedId, parentId: otherFolderId)
        // The union of a merge brought the moved member back into the folder's list.
        try appendStaleEntry(root, folderId: folderId, childId: movedId)
        // A child whose parent is the folder but which the folder does not list.
        let unlisted = try #require(root.editController.editModel(for: unlistedId))
        unlisted.parentId = folderId
        root.editController.save(updated: unlisted, message: "parent")

        root.editController.repairFolders(itemIds: [folderId])

        #expect(Set(childIds(root, of: folderId)) == [keptId, unlistedId])
        #expect(childIds(root, of: otherFolderId) == [movedId])
    }

    @Test("An item of the batch joins its folder when the folder does not list it (§9.8)")
    func batchItemJoinsItsFolder() async throws {
        let root = await makeRoot()
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let itemId = await addItem(root, name: "Item")
        let item = try #require(root.editController.editModel(for: itemId))
        item.parentId = folderId
        root.editController.save(updated: item, message: "parent")

        root.editController.repairFolders(itemIds: [itemId])

        #expect(childIds(root, of: folderId) == [itemId])
    }

    @Test("A member not known on this device stays listed (§9.8)")
    func unknownMemberStays() async throws {
        let root = await makeRoot()
        let folderId = await addItem(root, name: "Folder", type: .folder)
        let unknownId = UUID()
        try appendStaleEntry(root, folderId: folderId, childId: unknownId)

        root.editController.repairFolders(itemIds: [folderId])

        #expect(childIds(root, of: folderId) == [unknownId])
    }

    @Test("The Move/Add check agrees with the target list (§7.4)")
    func moveTargetCheckMatchesList() async {
        let root = await makeRoot()
        let controller = root.itemController
        #expect(!controller.hasCollections(isFolder: true, in: nil))

        let folderId = await addItem(root, name: "Folder", type: .folder)
        let nestedFolderId = await addItem(root, name: "Nested", type: .folder)
        root.editController.addItem(itemId: nestedFolderId, parentId: folderId)

        #expect(controller.hasCollections(isFolder: true, in: nil))
        #expect(controller.collections(isFolder: true, in: nil).map(\.id) == [folderId])
        #expect(controller.hasCollections(isFolder: true, in: folderId))
        #expect(!controller.hasCollections(isFolder: false, in: nil))
        #expect(controller.collections(isFolder: false, in: nil).isEmpty)
    }
}
