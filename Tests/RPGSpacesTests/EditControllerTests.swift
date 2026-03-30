// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct EditControllerTests {
    @Test func resetName() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name
        #expect(originalName == "3D Item")

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "Updated Item Name"
        await sut.reset(name: newName, itemId: item.id)

        #expect(item.name == newName)
        #expect(item.name == newName)
    }

    @Test func resetNameWithWhitespace() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "  Trimmed Name  "
        await sut.reset(name: newName, itemId: item.id)

        #expect(item.name == "Trimmed Name")
        #expect(item.name == "Trimmed Name")
    }

    @Test func resetCategory() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category
        #expect(originalCategory == .entry)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newCategory = ItemListCategory.building
        await sut.reset(category: newCategory, itemId: item.id)

        #expect(item.category == newCategory)
        #expect(item.category == newCategory)
    }

    @Test func resetCategoryNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same category should not trigger changes
        await sut.reset(category: originalCategory, itemId: item.id)

        #expect(item.category == originalCategory)
        #expect(item.category == originalCategory)
    }

    @Test func resetFileUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, itemId: item.id)

        #expect(item.fileUrl == newFileUrl)
        #expect(item.fileUrl == newFileUrl)
    }

    @Test func resetFileUrlForDifferentItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Create a new item
        let newItemId = await root.itemController.addNew(type: .item)
        let targetItem = await root.itemController.itemOrEmpty(for: newItemId)

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path2"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, itemId: targetItem.id)

        // The current model should remain unchanged
        #expect(item.fileUrl != newFileUrl)

        // The target item should have the new fileUrl
        let updatedTargetItem = await root.itemController.itemOrEmpty(for: targetItem.id)
        #expect(updatedTargetItem.fileUrl == newFileUrl)
    }

    @Test func resetSpaceWithNilUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset space with nil URL should remove the file URL
        await sut.resetFile(url: nil, itemId: item.id)

        #expect(item.fileUrl == nil)
        #expect(item.fileUrl == nil)
    }

    @Test func resetNameNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same name should not trigger changes
        await sut.reset(name: originalName, itemId: item.id)

        #expect(item.name == originalName)
        #expect(item.name == originalName)
    }

    @Test func addGroup() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent item
        let parentItemId = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItemId)
        #expect(parent.entries.count == 0)

        // Create child item to add to the group
        let childItemId = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childItemId)
        #expect(child.displayState == 0)

        // Add child to group
        await sut.addGroup(itemId: parent.id, childId: child.id)

        // Verify the child was added to the parent's entries
        #expect(parent.entries.count == 1)
        #expect(parent.entries[0].spaceId == child.id)
        #expect(parent.entries.count == 1)
        #expect(parent.entries[0].spaceId == child.id)

        // Verify child's display state was updated
        let updatedChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(updatedChild.displayState == 1)
    }

    @Test func addGroupMultipleChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent item
        let parentItemId = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItemId)

        // Create multiple child items
        let child1ItemId = await root.itemController.addNew(type: .item)
        let child1 = await root.itemController.itemOrEmpty(for: child1ItemId)

        let child2Item = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item)

        // Set current item to parent
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add first child
        await sut.addGroup(itemId: parent.id, childId: child1.id)
        #expect(parent.entries.count == 1)

        // Add second child
        await sut.addGroup(itemId: parent.id, childId: child2.id)
        #expect(parent.entries.count == 2)
        #expect(parent.entries.count == 2)

        // Verify both children are in the group
        let childIds = parent.entries.map { $0.spaceId }
        #expect(childIds.contains(child1.id))
        #expect(childIds.contains(child2.id))
    }

    @Test func addGroupIgnoresSameId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to add parent to itself - should be ignored
        await sut.addGroup(itemId: parent.id, childId: parent.id)

        #expect(parent.entries.count == 0)
        #expect(parent.entries.count == 0)
    }

    @Test func addGroupIgnoresDuplicateEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent and child items
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        let childItem = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childItem)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add child first time
        await sut.addGroup(itemId: parent.id, childId: child.id)
        #expect(parent.entries.count == 1)

        // Try to add same child again - should be ignored
        await sut.addGroup(itemId: parent.id, childId: child.id)
        #expect(parent.entries.count == 1)
        #expect(parent.entries.count == 1)
    }

    @Test func removeGroup() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent and child items
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        let childItem = await root.itemController.addNew(type: .item)
        let child = await root.itemController.itemOrEmpty(for: childItem)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add child to group
        await sut.addGroup(itemId: parent.id, childId: child.id)
        #expect(parent.entries.count == 1)
        let updatedChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(updatedChild.displayState == 1)

        // Remove child from group
        await sut.removeGroup(itemId: parent.id, childId: child.id)

        #expect(parent.entries.count == 0)
        #expect(parent.entries.count == 0)

        // Verify child's display state was reset
        let finalChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(finalChild.displayState == 0)
    }

    @Test func removeGroupFromMultiple() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent and multiple child items
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        let child1Item = await root.itemController.addNew(type: .item)
        let child1 = await root.itemController.itemOrEmpty(for: child1Item)

        let child2Item = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item)

        let child3Item = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.itemOrEmpty(for: child3Item)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add all children
        await sut.addGroup(itemId: parent.id, childId: child1.id)
        await sut.addGroup(itemId: parent.id, childId: child2.id)
        await sut.addGroup(itemId: parent.id, childId: child3.id)
        #expect(parent.entries.count == 3)

        // Remove middle child
        await sut.removeGroup(itemId: parent.id, childId: child2.id)

        #expect(parent.entries.count == 2)
        #expect(parent.entries.count == 2)

        // Verify remaining children
        let childIds = parent.entries.map { $0.spaceId }
        #expect(childIds.contains(child1.id))
        #expect(!childIds.contains(child2.id))
        #expect(childIds.contains(child3.id))

        // Verify removed child's display state
        let removedChild = await root.itemController.itemOrEmpty(for: child2.id)
        #expect(removedChild.displayState == 0)
    }

    @Test func removeGroupIgnoresSameId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to remove parent from itself - should be ignored
        await sut.removeGroup(itemId: parent.id, childId: parent.id)

        #expect(parent.entries.count == 0)
    }

    @Test func removeGroupNonExistentChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent and children
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        let child1Item = await root.itemController.addNew(type: .item)
        let child1 = await root.itemController.itemOrEmpty(for: child1Item)

        let child2Item = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add only child1 to group
        await sut.addGroup(itemId: parent.id, childId: child1.id)
        #expect(parent.entries.count == 1)

        // Try to remove child2 (not in group) - should have no effect
        await sut.removeGroup(itemId: parent.id, childId: child2.id)

        #expect(parent.entries.count == 1)
        #expect(parent.entries.count == 1)
        #expect(parent.entries[0].spaceId == child1.id)
    }

    @Test func addItemToFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create a regular item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        #expect(item.parentId == nil)

        // Add item to folder
        await sut.addItem(itemId: item.id, parentId: folderModel.id)

        // Verify the item was added to the folder's entries
        let updatedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(updatedFolder.entries.count == 1)
        #expect(updatedFolder.entries[0].spaceId == item.id)

        // Verify the item's parentId was updated
        let updatedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(updatedItem.parentId == folderModel.id)
    }

    @Test func addItemToCollection() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection (album for spaces)
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create a regular item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)

        // Add item to collection
        await sut.addItem(itemId: item.id, parentId: collectionModel.id)

        // Verify the item was added to the collection's entries
        let updatedCollection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(updatedCollection.entries.count == 1)
        #expect(updatedCollection.entries[0].spaceId == item.id)

        // For collections, parentId should NOT be updated (only folders set parentId)
        let updatedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(updatedItem.parentId == nil)
    }

    @Test func addItemToFolderMultipleItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create multiple items
        let item1 = await root.itemController.addNew(type: .item)
        let item2 = await root.itemController.addNew(type: .item)
        let item3 = await root.itemController.addNew(type: .item)

        // Add all items to folder
        await sut.addItem(itemId: item1, parentId: folderModel.id)
        await sut.addItem(itemId: item2, parentId: folderModel.id)
        await sut.addItem(itemId: item3, parentId: folderModel.id)

        // Verify all items were added
        let updatedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(updatedFolder.entries.count == 3)

        let entryIds = updatedFolder.entries.map { $0.spaceId }
        #expect(entryIds.contains(item1))
        #expect(entryIds.contains(item2))
        #expect(entryIds.contains(item3))

        // Verify all items have the correct parentId
        #expect(await root.itemController.itemOrEmpty(for: item1).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: item2).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: item3).parentId == folderModel.id)
    }

    @Test func addItemToFolderIgnoresSameId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Try to add folder to itself
        await sut.addItem(itemId: folderModel.id, parentId: folderModel.id)

        // Should have no entries (cannot add to itself)
        let updatedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(updatedFolder.entries.count == 0)
    }

    @Test func addItemToFolderIgnoresDuplicateParent() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)

        // Add item to folder first time
        await sut.addItem(itemId: item.id, parentId: folderModel.id)
        let folder1 = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder1.entries.count == 1)

        // Try to add same item again - should be ignored
        await sut.addItem(itemId: item.id, parentId: folderModel.id)
        let folder2 = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder2.entries.count == 1)
    }

    @Test func addItemToCollectionIgnoresSpecialCategory() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create a folder (special category)
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Try to add folder to collection - should be ignored (special category can't be in non-folder)
        await sut.addItem(itemId: folderModel.id, parentId: collectionModel.id)

        let updatedCollection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(updatedCollection.entries.count == 0)
    }

    @Test func addItemToFolderAllowsSpecialCategory() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create parent folder
        let parentFolderModel = SpaceModel(id: UUID(), name: "Parent Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: parentFolderModel, isInsert: true)

        // Create child folder (special category)
        let childFolderModel = SpaceModel(id: UUID(), name: "Child Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: childFolderModel, isInsert: true)

        // Add child folder to parent folder - should work (folders can contain folders)
        await sut.addItem(itemId: childFolderModel.id, parentId: parentFolderModel.id)

        let updatedParentFolder = await root.itemController.itemOrEmpty(for: parentFolderModel.id)
        #expect(updatedParentFolder.entries.count == 1)
        #expect(updatedParentFolder.entries[0].spaceId == childFolderModel.id)

        // Verify child folder's parentId was set
        let updatedChildFolder = await root.itemController.itemOrEmpty(for: childFolderModel.id)
        #expect(updatedChildFolder.parentId == parentFolderModel.id)
    }

    @Test func addItemWithNilParentId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)

        // Try to add item with nil parentId - should be ignored
        await sut.addItem(itemId: item.id, parentId: nil)

        // Item should remain unchanged
        let updatedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(updatedItem.parentId == nil)
    }

    @Test func addNewItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        let initialCount = await root.itemController.itemDataModel.items.count

        // Add new item
        let newItem = await sut.addNew(type: .item)

        #expect(newItem != nil)
        #expect(await root.itemController.itemDataModel.items.count == initialCount + 1)

        let item = newItem as? SpaceModel
        #expect(item?.category == .item)
    }

    @Test func addNewFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        let initialCount = await root.itemController.itemDataModel.items.count

        // Add new folder
        let newFolder = await sut.addNew(type: .folder)

        #expect(newFolder != nil)
        #expect(await root.itemController.itemDataModel.items.count == initialCount + 1)

        let folder = newFolder as? SpaceModel
        #expect(folder?.category == .folder)
    }

    @Test func addNewCollection() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        let initialCount = await root.itemController.itemDataModel.items.count

        // Add new collection
        let newCollection = await sut.addNew(type: .collection)

        #expect(newCollection != nil)
        #expect(await root.itemController.itemDataModel.items.count == initialCount + 1)

        let collection = newCollection as? SpaceModel
        #expect(collection?.category == .album) // album is the collection category for spaces
    }

    @Test func deleteItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        #expect(item.displayState == 0)

        // Delete the item
        await sut.delete(itemId: item.id)

        // Verify item is marked for deletion (displayState = 2)
        let deletedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(deletedItem.displayState == 2)
    }

    @Test func deleteItemWithChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a parent item
        let parentItem = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItem)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)

        // Add children to parent using addGroup
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))
        await sut.addGroup(itemId: parent.id, childId: child1)
        await sut.addGroup(itemId: parent.id, childId: child2)

        let updatedParent = await root.itemController.itemOrEmpty(for: parent.id)
        #expect(updatedParent.entries.count == 2)
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 1)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 1)

        // Delete the parent
        await sut.delete(itemId: parent.id)

        // Verify parent is marked for deletion
        let deletedParent = await root.itemController.itemOrEmpty(for: parent.id)
        #expect(deletedParent.displayState == 2)

        // Verify children's displayState is reset to 0
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 0)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 0)
    }

    @Test func deleteFolderWithChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)

        // Add children to folder
        await sut.addItem(itemId: child1, parentId: folderModel.id)
        await sut.addItem(itemId: child2, parentId: folderModel.id)

        #expect(await root.itemController.itemOrEmpty(for: child1).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child2).parentId == folderModel.id)

        // Delete the folder
        await sut.delete(itemId: folderModel.id)

        // Verify folder is marked for deletion
        let deletedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(deletedFolder.displayState == 2)

        // Verify children are also marked for deletion (displayState = 2)
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 2)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 2)

        // Verify children's parentId is reset to nil (moved to parent's parent, which is nil)
        #expect(await root.itemController.itemOrEmpty(for: child1).parentId == nil)
        #expect(await root.itemController.itemOrEmpty(for: child2).parentId == nil)
    }

    @Test func collectItemsForRemovalWithFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder with children
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)

        await sut.addItem(itemId: child1, parentId: folderModel.id)
        await sut.addItem(itemId: child2, parentId: folderModel.id)

        // Test collectItemsForRemoval
        let removingItems = [ItemRowModel(itemId: folderModel.id, typeId: .space)]
        let allItems = await sut.markCollectionItemsForRemoval(for: removingItems)

        // Should include folder + 2 children = 3 items
        #expect(allItems.count == 3)
        #expect(allItems.contains(where: { $0.itemId == folderModel.id }))
        #expect(allItems.contains(where: { $0.itemId == child1 }))
        #expect(allItems.contains(where: { $0.itemId == child2 }))
    }

    @Test func collectItemsForRemovalWithNestedFolders() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create nested folder structure: parent > child folder > grandchild item
        let parentFolder = SpaceModel(id: UUID(), name: "Parent Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: parentFolder, isInsert: true)

        let childFolder = SpaceModel(id: UUID(), name: "Child Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: childFolder, isInsert: true)

        let grandchildItem = await root.itemController.addNew(type: .item)

        // Build hierarchy
        await sut.addItem(itemId: grandchildItem, parentId: childFolder.id)
        await sut.addItem(itemId: childFolder.id, parentId: parentFolder.id)

        // Test collectItemsForRemoval on parent folder
        let removingItems = [ItemRowModel(itemId: parentFolder.id, typeId: .space)]
        let allItems = await sut.markCollectionItemsForRemoval(for: removingItems)

        // Should include parent folder + child folder + grandchild item = 3 items
        #expect(allItems.count == 3)
        #expect(allItems.contains(where: { $0.itemId == parentFolder.id }))
        #expect(allItems.contains(where: { $0.itemId == childFolder.id }))
        #expect(allItems.contains(where: { $0.itemId == grandchildItem }))
    }

    @Test func collectItemsForRemovalWithCollection() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection with items
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        let item1 = await root.itemController.addNew(type: .item)
        let item2 = await root.itemController.addNew(type: .item)

        await sut.addItem(itemId: item1, parentId: collectionModel.id)
        await sut.addItem(itemId: item2, parentId: collectionModel.id)

        // Test collectItemsForRemoval
        let removingItems = [ItemRowModel(itemId: collectionModel.id, typeId: .space)]
        let allItems = await sut.markCollectionItemsForRemoval(for: removingItems)

        // Should only include collection, NOT items (collections don't delete children)
        #expect(allItems.count == 1)
        #expect(allItems[0].itemId == collectionModel.id)
    }

    @Test func deleteCollectionWithItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection (album)
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create items
        let item1 = await root.itemController.addNew(type: .item)
        let item2 = await root.itemController.addNew(type: .item)

        // Add items to collection
        await sut.addItem(itemId: item1, parentId: collectionModel.id)
        await sut.addItem(itemId: item2, parentId: collectionModel.id)

        let collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 2)
        #expect(await root.itemController.itemOrEmpty(for: item1).parentId == nil) // collections don't set parentId
        #expect(await root.itemController.itemOrEmpty(for: item2).parentId == nil)

        // Delete the collection
        await sut.delete(itemId: collectionModel.id)

        // Verify collection is marked for deletion
        let deletedCollection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(deletedCollection.displayState == 2)

        // Verify items remain visible (displayState = 0), not deleted
        #expect(await root.itemController.itemOrEmpty(for: item1).displayState == 0)
        #expect(await root.itemController.itemOrEmpty(for: item2).displayState == 0)

        // Verify items' parentId remains nil (collections don't set parentId)
        #expect(await root.itemController.itemOrEmpty(for: item1).parentId == nil)
        #expect(await root.itemController.itemOrEmpty(for: item2).parentId == nil)
    }

    @Test func duplicate() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))
        await sut.reset(name: "Original Item", itemId: item.id)

        let originalItem = await root.itemController.itemOrEmpty(for: item.id)
        let initialCount = await root.itemController.itemDataModel.items.count

        // Duplicate the item
        await sut.duplicate(item: originalItem)

        // Wait a bit for async operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify a new item was created
        let newCount = await root.itemController.itemDataModel.items.count
        #expect(newCount == initialCount + 1)
    }

    @Test func markForDeletion() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)
        #expect(item.displayState == 0)

        // Mark for deletion
        await sut.markForDeletion(itemId: item.id)

        // Verify item is marked for deletion
        let markedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(markedItem.displayState == 2)
    }

    @Test func restore() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create an item
        let itemId = await root.itemController.addNew(type: .item)
        let item = await root.itemController.itemOrEmpty(for: itemId)

        // Mark for deletion
        await sut.markForDeletion(itemId: item.id)
        #expect(await root.itemController.itemOrEmpty(for: item.id).displayState == 2)

        // Restore the item
        await sut.restore(itemId: item.id)

        // Verify item is restored
        let restoredItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(restoredItem.displayState == 0)
    }

    @Test func restoreFolderWithChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)

        // Add children to folder
        await sut.addItem(itemId: child1, parentId: folderModel.id)
        await sut.addItem(itemId: child2, parentId: folderModel.id)

        // Delete the folder (which affects children)
        await sut.delete(itemId: folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: folderModel.id).displayState == 2)

        // Restore the folder
        await sut.restore(itemId: folderModel.id)

        // Verify folder is restored
        let restoredFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(restoredFolder.displayState == 0)

        // Verify children's parentId is set back to folder and displayState is hidden (1)
        #expect(await root.itemController.itemOrEmpty(for: child1).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child2).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 1)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 1)
    }

    @Test func removeItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)

        // Add children to collection
        await sut.addItem(itemId: child1, parentId: collectionModel.id)
        await sut.addItem(itemId: child2, parentId: collectionModel.id)
        await sut.addItem(itemId: child3, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // Remove the middle entry (index 1)
        await sut.removeItem(offsets: IndexSet(integer: 1), itemId: collection.id)

        // Verify entry was removed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 2)

        let entryIds = collection.entries.map { $0.spaceId }
        #expect(entryIds.contains(child1))
        #expect(!entryIds.contains(child2))
        #expect(entryIds.contains(child3))

        // For collection, child should NOT be deleted (displayState still 0)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 0)
    }

    @Test func removeItemFromFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)

        // Add children to folder
        await sut.addItem(itemId: child1, parentId: folderModel.id)
        await sut.addItem(itemId: child2, parentId: folderModel.id)
        await sut.addItem(itemId: child3, parentId: folderModel.id)

        var folder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder.entries.count == 3)

        // Remove the middle entry (index 1) from folder
        await sut.removeItem(offsets: IndexSet(integer: 1), itemId: folder.id)

        // Verify entry was removed from folder
        folder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder.entries.count == 2)

        // For folder, removed child should be moved to root level (parentId = nil) and remain visible (displayState = 0)
        let removedChild = await root.itemController.itemOrEmpty(for: child2)
        #expect(removedChild.parentId == nil)
        #expect(removedChild.displayState == 0)
    }

    @Test func removeMultipleItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)
        let child4 = await root.itemController.addNew(type: .item)

        // Add children to collection
        await sut.addItem(itemId: child1, parentId: collectionModel.id)
        await sut.addItem(itemId: child2, parentId: collectionModel.id)
        await sut.addItem(itemId: child3, parentId: collectionModel.id)
        await sut.addItem(itemId: child4, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // Remove multiple entries (indices 1 and 2)
        await sut.removeItem(offsets: IndexSet([1, 2]), itemId: collection.id)

        // Verify entries were removed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 2)

        let entryIds = collection.entries.map { $0.spaceId }
        #expect(entryIds.contains(child1))
        #expect(!entryIds.contains(child2))
        #expect(!entryIds.contains(child3))
        #expect(entryIds.contains(child4))
    }

    @Test func moveItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)

        // Add children to collection
        await sut.addItem(itemId: child1, parentId: collectionModel.id)
        await sut.addItem(itemId: child2, parentId: collectionModel.id)
        await sut.addItem(itemId: child3, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // Original order: child1, child2, child3
        #expect(collection.entries[0].spaceId == child1)
        #expect(collection.entries[1].spaceId == child2)
        #expect(collection.entries[2].spaceId == child3)

        // Move first item (index 0) to position 2 (after child2)
        await sut.moveItems(source: IndexSet(integer: 0), destination: 2, itemId: collection.id)

        // Verify order changed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // New order should be: child2, child1, child3
        #expect(collection.entries[0].spaceId == child2)
        #expect(collection.entries[1].spaceId == child1)
        #expect(collection.entries[2].spaceId == child3)
    }

    @Test func deleteFolderWithSelectiveChildRemoval() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a folder with multiple children
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)

        await sut.addItem(itemId: child1, parentId: folderModel.id)
        await sut.addItem(itemId: child2, parentId: folderModel.id)
        await sut.addItem(itemId: child3, parentId: folderModel.id)

        #expect(await root.itemController.itemOrEmpty(for: child1).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child2).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child3).parentId == folderModel.id)

        // Simulate the actual UI workflow:
        // 1. Mark all for deletion (what markCollectionItemsForRemoval does)
        await sut.markForDeletion(itemId: folderModel.id)
        await sut.markForDeletion(itemId: child1)
        await sut.markForDeletion(itemId: child2)
        await sut.markForDeletion(itemId: child3)

        #expect(await root.itemController.itemOrEmpty(for: folderModel.id).displayState == 2)
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 2)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 2)
        #expect(await root.itemController.itemOrEmpty(for: child3).displayState == 2)

        // 2. User clicks Remove with only folder and child1 selected (child2 and child3 unchecked)
        //    This simulates EffectedLinkActionPanelView behavior (lines 40-46):
        //    First: removeItems(models: removedItems) → delete folder and child1
        //    Then: restoreItems(models: restoredItems) → restore child2 and child3

        // Delete folder (this will also mark ALL children including child2 and child3 as deleted)
        await sut.delete(itemId: folderModel.id)

        // Restore child2 and child3 AFTER folder is deleted
        // The restore() function will now check if parent is deleted and move them to root
        await sut.restore(itemId: child2)
        await sut.restore(itemId: child3)

        // child1 remains marked for deletion (displayState == 2)

        // Verify folder is deleted
        let deletedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(deletedFolder.displayState == 2)

        // Child1 should remain deleted
        #expect(await root.itemController.itemOrEmpty(for: child1).displayState == 2)

        // Child2 and child3 should be moved to root level (parentId = nil) and visible (displayState = 0)
        #expect(await root.itemController.itemOrEmpty(for: child2).parentId == nil)
        #expect(await root.itemController.itemOrEmpty(for: child3).parentId == nil)
        #expect(await root.itemController.itemOrEmpty(for: child2).displayState == 0)
        #expect(await root.itemController.itemOrEmpty(for: child3).displayState == 0)
    }

    @Test func moveMultipleItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        // Create children
        let child1 = await root.itemController.addNew(type: .item)
        let child2 = await root.itemController.addNew(type: .item)
        let child3 = await root.itemController.addNew(type: .item)
        let child4 = await root.itemController.addNew(type: .item)

        // Add children to collection
        await sut.addItem(itemId: child1, parentId: collectionModel.id)
        await sut.addItem(itemId: child2, parentId: collectionModel.id)
        await sut.addItem(itemId: child3, parentId: collectionModel.id)
        await sut.addItem(itemId: child4, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // Original order: child1, child2, child3, child4
        #expect(collection.entries[0].spaceId == child1)
        #expect(collection.entries[1].spaceId == child2)
        #expect(collection.entries[2].spaceId == child3)
        #expect(collection.entries[3].spaceId == child4)

        // Move items at indices 0 and 1 (child1, child2) to position 3
        await sut.moveItems(source: IndexSet([0, 1]), destination: 3, itemId: collection.id)

        // Verify order changed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // New order should be: child3, child1, child2, child4
        #expect(collection.entries[0].spaceId == child3)
        #expect(collection.entries[1].spaceId == child1)
        #expect(collection.entries[2].spaceId == child2)
        #expect(collection.entries[3].spaceId == child4)
    }

    @Test func addGroupIgnoresFolderAsChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a parent item (group container)
        let parentItemId = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItemId)
        #expect(parent.entries.count == 0)

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to add folder to group - should be ignored
        await sut.addGroup(itemId: parent.id, childId: folderModel.id)

        // Verify folder was NOT added to parent's entries
        #expect(parent.entries.count == 0)

        // Verify folder's display state was NOT updated
        let folder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder.displayState == 0)
    }

    @Test func addGroupIgnoresCollectionAsChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = await root.editController

        // Create a parent item (group container)
        let parentItemId = await root.itemController.addNew(type: .item)
        let parent = await root.itemController.itemOrEmpty(for: parentItemId)
        #expect(parent.entries.count == 0)

        // Create a collection (album for spaces)
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to add collection to group - should be ignored
        await sut.addGroup(itemId: parent.id, childId: collectionModel.id)

        // Verify collection was NOT added to parent's entries
        #expect(parent.entries.count == 0)

        // Verify collection's display state was NOT updated
        let collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.displayState == 0)
    }
}

