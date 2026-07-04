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

@MainActor
struct EditControllerTests {

    @MainActor
    private func captureIds(_ root: CharacterRootModel) -> Set<UUID> {
        Set(root.itemController.itemDataModel.items)
    }

    private func requireSingleNewId(before: Set<UUID>, root: CharacterRootModel) async throws -> UUID {
        let added = captureIds(root).subtracting(before)
        return try #require(added.first, "Expected exactly one new item but found \(added.count)")
    }

    @MainActor
    private func firstId(in ids: Set<UUID>, of root: CharacterRootModel, where predicate: (ValueModel) -> Bool) -> UUID? {
        ids.first { predicate(root.itemController.itemOrEmpty(for: $0)) }
    }

    // MARK: - addNewGroup

    @Test func addNewGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let groupEntry = try #require(item.entries.first(where: { $0.id == entryId }))
        let groupItemId = try #require(groupEntry.valueId)

        let groupItem = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupItem.groupId == itemId)
        #expect(groupItem.parentId == nil)
        #expect(groupItem.displayState == 1)
    }

    // MARK: - willDeleteChildren (called from delete)

    @Test func deleteNonFolderContainerClearsGroupIdOnChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create a parent item and a group child
        let parentId = await root.itemController.addNew(type: .item)
        let childId = await sut.addNewGroup(itemId: parentId)

        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == childId }))
        let groupItemId = try #require(groupEntry.valueId)

        // Precondition: child has groupId set
        let childBefore = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childBefore.groupId == parentId)

        // Delete the parent (non-folder)
        await sut.delete(itemId: parentId)

        // groupId on the child must be cleared
        let childAfter = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childAfter.groupId == nil)
        // New behavior: delete() resets displayState to 0 (unhides group children)
        #expect(childAfter.displayState == 0)
    }

    // MARK: - willRestore

    @Test func restoreGroupItemClearsGroupIdWhenGroupDeleted() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Mark parent for deletion using markForDeletion (new behavior)
        sut.markForDeletion(itemId: parentId)

        // Manually set the child back to deleted so restore can run
        let child = root.itemController.itemOrEmpty(for: childId)
        child.displayState = 2
        root.itemController.replace(model: child, isInsert: false)

        // Verify child has groupId pointing to deleted parent
        #expect(child.groupId == parentId)

        // Restore the child
        sut.restore(itemId: childId)

        let restoredChild = root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        
        // The willRestore implementation (line 361) checks if groupId parent is deleted and clears it
        // This is the CORRECT behavior - groupId should be nil when parent is deleted
        #expect(restoredChild.groupId == nil)
    }

    @Test func restoreGroupItemKeepsGroupIdWhenGroupAlive() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Soft-delete only the child
        let child = root.itemController.itemOrEmpty(for: childId)
        child.displayState = 2
        root.itemController.replace(model: child, isInsert: false)

        // Restore the child
        sut.restore(itemId: childId)

        let restoredChild = root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        // Parent is alive → groupId stays
        #expect(restoredChild.groupId == parentId)
    }

    // MARK: - isOrphanedHidden

    @Test func isOrphanedHiddenReturnsTrueWhenHiddenWithNoParentAndNoGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId = nil
        root.itemController.replace(model: item, isInsert: false)

        let result = sut.isOrphanedHidden(itemId: itemId)
        #expect(result == true)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenGroupIdIsSet() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // addNewGroup produces a hidden item with groupId set — must NOT be considered orphaned
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let result = sut.isOrphanedHidden(itemId: childId)
        #expect(result == false)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenVisible() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        // displayState 0 = visible
        let result = sut.isOrphanedHidden(itemId: itemId)
        #expect(result == false)
    }

    // MARK: - parentFolder

    @Test func parentFolderResolvesGroupIdFirst() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let folder = sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == parentId)
    }

    @Test func parentFolderFallsBackToParentIdWhenNoGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let child = root.itemController.itemOrEmpty(for: childId)
        child.parentId = folderId
        child.groupId = nil
        root.itemController.replace(model: child, isInsert: false)

        let folder = sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == folderId)
    }

    @Test func parentFolderReturnsNilWhenNeitherGroupIdNorParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let folder = sut.parentFolder(itemId: itemId)
        #expect(folder == nil)
    }

    // MARK: - duplicate with groups (groupId propagation)

    @Test func duplicateWithGroupsSetsGroupIdOnCopies() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Build: parent → group entry → child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let copiedId = await sut.duplicate(itemId: parentId, withCopy: true)
        let copiedParent = root.itemController.itemOrEmpty(for: copiedId)
        #expect(copiedParent.id != parentId)
        #expect(copiedParent.groupId == nil)

        // The copied group child must point to the copy, not the original
        let copiedEntry = try #require(copiedParent.entries.first)
        let copiedChildId = try #require(copiedEntry.valueId)
        #expect(copiedChildId != childId)

        let copiedChild = root.itemController.itemOrEmpty(for: copiedChildId)
        #expect(copiedChild.groupId == copiedId)
        #expect(copiedChild.groupId != parentId)
    }

    // MARK: - addItem (folder membership + parentId)

    @Test func addItemSetsParentIdAndFolderContainsAllChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Empty folder — no children yet
        let folderId = await root.itemController.addNew(type: .folder)
        let emptyFolder = root.itemController.itemOrEmpty(for: folderId)
        #expect(emptyFolder.entries.isEmpty)

        // Add item1 → folder must list it and parentId must be set
        let item1Id = await root.itemController.addNew(type: .item)
        sut.addItem(itemId: item1Id, parentId: folderId)

        let item1 = root.itemController.itemOrEmpty(for: item1Id)
        #expect(item1.parentId == folderId)

        let folderAfterItem1 = root.itemController.itemOrEmpty(for: folderId)
        #expect(folderAfterItem1.entries.contains(where: { $0.childId == item1Id }))

        // Create item2 but do NOT add it yet
        let item2Id = await root.itemController.addNew(type: .item)

        // Add item3 before item2 to verify out-of-order insertion still works
        let item3Id = await root.itemController.addNew(type: .item)
        sut.addItem(itemId: item3Id, parentId: folderId)

        // Now add the previously skipped item2
        sut.addItem(itemId: item2Id, parentId: folderId)

        // All three must have parentId pointing to the folder
        let finalItem1 = root.itemController.itemOrEmpty(for: item1Id)
        let finalItem2 = root.itemController.itemOrEmpty(for: item2Id)
        let finalItem3 = root.itemController.itemOrEmpty(for: item3Id)

        #expect(finalItem1.parentId == folderId)
        #expect(finalItem2.parentId == folderId)
        #expect(finalItem3.parentId == folderId)

        // Folder entries must contain all three items
        let finalFolder = root.itemController.itemOrEmpty(for: folderId)
        #expect(finalFolder.entries.count == 3)
        #expect(finalFolder.entries.contains(where: { $0.childId == item1Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item2Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item3Id }))
    }

    // MARK: - delete / restore round-trip

    @Test func deleteAndRestorePlainItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "TestItem", itemId: itemId)

        // Use markForDeletion to set displayState = 2
        sut.markForDeletion(itemId: itemId)
        let deleted = root.itemController.itemOrEmpty(for: itemId)
        #expect(deleted.displayState == 2)

        sut.restore(itemId: itemId)
        let restored = root.itemController.itemOrEmpty(for: itemId)
        #expect(restored.displayState == 0)
        #expect(restored.parentId == nil)
        #expect(restored.groupId == nil)
    }

    // MARK: - duplicate(item:) — shared behaviour with AudioRPG

    @Test("Duplicating a normal item copies all properties except id; name gets Copy suffix; parentId cleared")
    func duplicatingNormalItemCopiesAllPropertiesExceptId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.reset(description: "A brave hero", itemId: itemId)
        sut.reset(tags: ["warrior", "brave"], itemId: itemId)
        let original = root.itemController.itemOrEmpty(for: itemId)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != original.id)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.description == original.description)
        #expect(dup.tags == original.tags)
        #expect(dup.category == original.category)
        #expect(dup.displayState == original.displayState)
        #expect(dup.parentId == nil)
        #expect(dup.groupId == nil)
    }

    @Test("Duplicating a collection copies all properties; entries keep references to the same child items")
    func duplicatingCollectionCopiesAllPropertiesAndKeepsEntryReferences() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let collectionId = await root.itemController.addNew(type: .collection)
        sut.reset(name: "My Collection", itemId: collectionId)
        sut.reset(tags: ["heroes"], itemId: collectionId)
        let memberId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: memberId)
        sut.addGroup(itemId: collectionId, childId: memberId)

        let original = root.itemController.itemOrEmpty(for: collectionId)
        try #require(original.entries.count == 1)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != collectionId)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.category == original.category)
        #expect(dup.tags == original.tags)
        #expect(dup.entries.count == original.entries.count)
        // Entries are references — both collections point to the same member
        #expect(dup.entries.map(\.childId) == original.entries.map(\.childId))
    }

    @Test("Duplicating a folder creates a new folder with independently duplicated children — new child IDs, correct parentId")
    func duplicatingFolderDuplicatesChildrenIntoNewFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let child1Id = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character 1", itemId: child1Id)
        sut.addItem(itemId: child1Id, parentId: folderId)
        let child2Id = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character 2", itemId: child2Id)
        sut.addItem(itemId: child2Id, parentId: folderId)

        let original = root.itemController.itemOrEmpty(for: folderId)
        try #require(original.entries.count == 2)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let newIds = captureIds(root).subtracting(before)

        let dupFolderId = try #require(firstId(in: newIds, of: root) { $0.category == .folder })
        let dupFolder = root.itemController.itemOrEmpty(for: dupFolderId)
        #expect(dupFolder.id != folderId)
        #expect(dupFolder.name.hasSuffix("Copy"))
        #expect(dupFolder.category == .folder)
        #expect(dupFolder.parentId == original.parentId)
        #expect(dupFolder.entries.count == 2)

        // New folder must reference new children, not the originals
        let dupChildIds = Set(dupFolder.entries.map(\.childId))
        #expect(!dupChildIds.contains(child1Id))
        #expect(!dupChildIds.contains(child2Id))
        for childId in dupChildIds {
            let child = root.itemController.itemOrEmpty(for: childId)
            #expect(child.parentId == dupFolderId)
        }
    }

    @Test("Duplicating an item inside a folder: duplicate keeps the same parentId and is added to the parent folder")
    func duplicatingItemInFolderPreservesParentAndIsAddedToFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addItem(itemId: itemId, parentId: folderId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.parentId == folderId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.parentId == folderId)
        let folder = root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.contains(where: { $0.childId == dupId }))
    }

    @Test("Duplicating a collection member adds the new item as a child reference in that collection")
    func duplicatingCollectionMemberAddsNewReferenceToCollection() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let collectionId = await root.itemController.addNew(type: .collection)
        sut.reset(name: "My Collection", itemId: collectionId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addGroup(itemId: collectionId, childId: itemId)

        let collection = root.itemController.itemOrEmpty(for: collectionId)
        try #require(collection.entries.count == 1)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let before = captureIds(root)
        await sut.duplicate(item: item)
        let dupId = try await requireSingleNewId(before: before, root: root)

        let updatedCollection = root.itemController.itemOrEmpty(for: collectionId)
        #expect(updatedCollection.entries.count == 2)
        #expect(updatedCollection.entries.contains(where: { $0.childId == dupId }))
    }

    // MARK: - duplicate(item:) — CharacterRPG-specific: group sub-items

    @Test("Duplicating an item with group sub-items copies the groups; new groups have groupId pointing to the duplicate")
    func duplicatingItemWithGroupsCopiesGroupsWithNewGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entry1Id = await sut.addNewGroup(itemId: itemId)
        let entry2Id = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let entry1 = try #require(item.entries.first(where: { $0.id == entry1Id }))
        let originalGroup1Id = try #require(entry1.valueId)
        let entry2 = try #require(item.entries.first(where: { $0.id == entry2Id }))
        let originalGroup2Id = try #require(entry2.valueId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let newIds = captureIds(root).subtracting(before)

        // The main duplicate has groupId == nil; group copies have groupId set
        let dupItemId = try #require(firstId(in: newIds, of: root) { $0.groupId == nil })
        let dupItem = root.itemController.itemOrEmpty(for: dupItemId)
        #expect(dupItem.id != itemId)
        #expect(dupItem.name.hasSuffix("Copy"))
        #expect(dupItem.entries.count == 2)

        for entry in dupItem.entries {
            let newGroupId = try #require(entry.valueId)
            // Each group is a new item, not the original
            #expect(newGroupId != originalGroup1Id)
            #expect(newGroupId != originalGroup2Id)
            let newGroup = root.itemController.itemOrEmpty(for: newGroupId)
            // New group's groupId points to the duplicate, not the original
            #expect(newGroup.groupId == dupItemId)
            #expect(newGroup.groupId != itemId)
            #expect(newGroup.displayState == 1)
        }
    }

    @Test("Duplicating an item with groups inside a folder: groups are copied and item is added to the same folder")
    func duplicatingItemWithGroupsInFolderCopiesGroupsAndAddsToFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addItem(itemId: itemId, parentId: folderId)
        let entryId = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let groupEntry = try #require(item.entries.first(where: { $0.id == entryId }))
        let originalGroupId = try #require(groupEntry.valueId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let newIds = captureIds(root).subtracting(before)

        let dupItemId = try #require(firstId(in: newIds, of: root) { $0.groupId == nil })
        let dupItem = root.itemController.itemOrEmpty(for: dupItemId)

        // Duplicate is in the same folder
        #expect(dupItem.parentId == folderId)
        let folder = root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.contains(where: { $0.childId == dupItemId }))

        // Group is a new copy with groupId pointing to the duplicate
        let dupEntry = try #require(dupItem.entries.first)
        let newGroupId = try #require(dupEntry.valueId)
        #expect(newGroupId != originalGroupId)
        let newGroup = root.itemController.itemOrEmpty(for: newGroupId)
        #expect(newGroup.groupId == dupItemId)
    }
}
