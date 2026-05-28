// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct EditControllerTests {

    // MARK: - addNewGroup

    @Test func addNewGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: itemId)

        let item = await root.itemController.itemOrEmpty(for: itemId)
        let groupEntry = try #require(item.entries.first(where: { $0.id == entryId }))
        let groupItemId = try #require(groupEntry.valueId)

        let groupItem = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupItem.groupId == itemId)
        #expect(groupItem.parentId == nil)
        #expect(groupItem.displayState == 1)
    }

    // MARK: - willDeleteChildren (called from delete)

    @Test func deleteNonFolderContainerClearsGroupIdOnChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // Create a parent item and a group child
        let parentId = await root.itemController.addNew(type: .item)
        let childId = await sut.addNewGroup(itemId: parentId)

        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == childId }))
        let groupItemId = try #require(groupEntry.valueId)

        // Precondition: child has groupId set
        let childBefore = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childBefore.groupId == parentId)

        // Delete the parent (non-folder)
        await sut.delete(itemId: parentId)

        // groupId on the child must be cleared
        let childAfter = await root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childAfter.groupId == nil)
        // group children stay hidden (displayState 1) — the base delete loop does not reset valueId-based children
        #expect(childAfter.displayState == 1)
    }

    // MARK: - willRestore

    @Test func restoreGroupItemClearsGroupIdWhenGroupDeleted() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Soft-delete the parent (displayState 2)
        await sut.delete(itemId: parentId)

        // Manually set the child back to deleted so restore can run
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.groupId = parentId  // re-attach to the deleted parent for the test
        child.displayState = 2
        await root.itemController.replace(model: child, isInsert: false)

        // Restore the child
        await sut.restore(itemId: childId)

        let restoredChild = await root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        // groupId must be cleared because parent was deleted
        #expect(restoredChild.groupId == nil)
    }

    @Test func restoreGroupItemKeepsGroupIdWhenGroupAlive() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Soft-delete only the child
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.displayState = 2
        await root.itemController.replace(model: child, isInsert: false)

        // Restore the child
        await sut.restore(itemId: childId)

        let restoredChild = await root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        // Parent is alive → groupId stays
        #expect(restoredChild.groupId == parentId)
    }

    // MARK: - isOrphanedHidden

    @Test func isOrphanedHiddenReturnsTrueWhenHiddenWithNoParentAndNoGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId = nil
        await root.itemController.replace(model: item, isInsert: false)

        let result = await sut.isOrphanedHidden(itemId: itemId)
        #expect(result == true)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenGroupIdIsSet() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // addNewGroup produces a hidden item with groupId set — must NOT be considered orphaned
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let result = await sut.isOrphanedHidden(itemId: childId)
        #expect(result == false)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenVisible() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        // displayState 0 = visible
        let result = await sut.isOrphanedHidden(itemId: itemId)
        #expect(result == false)
    }

    // MARK: - parentFolder

    @Test func parentFolderResolvesGroupIdFirst() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let folder = await sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == parentId)
    }

    @Test func parentFolderFallsBackToParentIdWhenNoGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childId)
        child.parentId = folderId
        child.groupId = nil
        await root.itemController.replace(model: child, isInsert: false)

        let folder = await sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == folderId)
    }

    @Test func parentFolderReturnsNilWhenNeitherGroupIdNorParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let folder = await sut.parentFolder(itemId: itemId)
        #expect(folder == nil)
    }

    // MARK: - duplicate with groups (groupId propagation)

    @Test func duplicateWithGroupsSetsGroupIdOnCopies() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // Build: parent → group entry → child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = await root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let copiedId = await sut.duplicate(itemId: parentId, withCopy: true)
        let copiedParent = await root.itemController.itemOrEmpty(for: copiedId)
        #expect(copiedParent.id != parentId)
        #expect(copiedParent.groupId == nil)

        // The copied group child must point to the copy, not the original
        let copiedEntry = try #require(copiedParent.entries.first)
        let copiedChildId = try #require(copiedEntry.valueId)
        #expect(copiedChildId != childId)

        let copiedChild = await root.itemController.itemOrEmpty(for: copiedChildId)
        #expect(copiedChild.groupId == copiedId)
        #expect(copiedChild.groupId != parentId)
    }

    // MARK: - addItem (folder membership + parentId)

    @Test func addItemSetsParentIdAndFolderContainsAllChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        // Empty folder — no children yet
        let folderId = await root.itemController.addNew(type: .folder)
        let emptyFolder = await root.itemController.itemOrEmpty(for: folderId)
        #expect(emptyFolder.entries.isEmpty)

        // Add item1 → folder must list it and parentId must be set
        let item1Id = await root.itemController.addNew(type: .item)
        await sut.addItem(itemId: item1Id, parentId: folderId)

        let item1 = await root.itemController.itemOrEmpty(for: item1Id)
        #expect(item1.parentId == folderId)

        let folderAfterItem1 = await root.itemController.itemOrEmpty(for: folderId)
        #expect(folderAfterItem1.entries.contains(where: { $0.childId == item1Id }))

        // Create item2 but do NOT add it yet
        let item2Id = await root.itemController.addNew(type: .item)

        // Add item3 before item2 to verify out-of-order insertion still works
        let item3Id = await root.itemController.addNew(type: .item)
        await sut.addItem(itemId: item3Id, parentId: folderId)

        // Now add the previously skipped item2
        await sut.addItem(itemId: item2Id, parentId: folderId)

        // All three must have parentId pointing to the folder
        let finalItem1 = await root.itemController.itemOrEmpty(for: item1Id)
        let finalItem2 = await root.itemController.itemOrEmpty(for: item2Id)
        let finalItem3 = await root.itemController.itemOrEmpty(for: item3Id)

        #expect(finalItem1.parentId == folderId)
        #expect(finalItem2.parentId == folderId)
        #expect(finalItem3.parentId == folderId)

        // Folder entries must contain all three items
        let finalFolder = await root.itemController.itemOrEmpty(for: folderId)
        #expect(finalFolder.entries.count == 3)
        #expect(finalFolder.entries.contains(where: { $0.childId == item1Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item2Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item3Id }))
    }

    // MARK: - delete / restore round-trip

    @Test func deleteAndRestorePlainItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let itemId = await root.itemController.addNew(type: .item)
        await sut.reset(name: "TestItem", itemId: itemId)

        await sut.delete(itemId: itemId)
        let deleted = await root.itemController.itemOrEmpty(for: itemId)
        #expect(deleted.displayState == 2)

        await sut.restore(itemId: itemId)
        let restored = await root.itemController.itemOrEmpty(for: itemId)
        #expect(restored.displayState == 0)
        #expect(restored.parentId == nil)
        #expect(restored.groupId == nil)
    }
}
