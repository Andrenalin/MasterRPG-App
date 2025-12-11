// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct EditControllerTests {
    @Test func resetName() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name
        #expect(originalName == "3D Item")

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "Updated Item Name"
        await sut.reset(name: newName)

        #expect(await sut.model.name == newName)
        #expect(item.name == newName)
    }

    @Test func resetNameWithWhitespace() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "  Trimmed Name  "
        await sut.reset(name: newName)

        #expect(await sut.model.name == "Trimmed Name")
        #expect(item.name == "Trimmed Name")
    }

    @Test func resetCategory() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category
        #expect(originalCategory == .item)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newCategory = ItemListCategory.building
        await sut.reset(category: newCategory)

        #expect(await sut.model.category == newCategory)
        #expect(item.category == newCategory)
    }

    @Test func resetCategoryNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same category should not trigger changes
        await sut.reset(category: originalCategory)

        #expect(await sut.model.category == originalCategory)
        #expect(item.category == originalCategory)
    }

    @Test func resetFileUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, for: item.id)

        #expect(await sut.model.fileUrl == newFileUrl)
        #expect(item.fileUrl == newFileUrl)
    }

    @Test func resetFileUrlForDifferentItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Create a new item
        let newItem = await root.itemController.addNew(type: nil)
        let targetItem = await root.itemController.itemOrEmpty(for: newItem.itemId)

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path2"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, for: targetItem.id)

        // The current model should remain unchanged
        #expect(await sut.model.id == item.id)
        #expect(await sut.model.fileUrl != newFileUrl)

        // The target item should have the new fileUrl
        let updatedTargetItem = await root.itemController.itemOrEmpty(for: targetItem.id)
        #expect(updatedTargetItem.fileUrl == newFileUrl)
    }

    @Test func resetSpaceWithNilUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset space with nil URL should remove the file URL
        sut.resetSpace(url: nil)

        #expect(await sut.model.fileUrl == nil)
        #expect(item.fileUrl == nil)
    }

    @Test func resetNameNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same name should not trigger changes
        await sut.reset(name: originalName)

        #expect(await sut.model.name == originalName)
        #expect(item.name == originalName)
    }

    @Test func addGroup() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)
        #expect(parent.entries.count == 0)

        // Create child item to add to the group
        let childItem = await root.itemController.addNew(type: nil)
        let child = await root.itemController.itemOrEmpty(for: childItem.itemId)
        #expect(child.displayState == 0)

        // Set current item to parent
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add child to group
        await sut.addGroup(childId: child.id)

        // Verify the child was added to the parent's entries
        #expect(await sut.model.entries.count == 1)
        #expect(await sut.model.entries[0].spaceId == child.id)
        #expect(parent.entries.count == 1)
        #expect(parent.entries[0].spaceId == child.id)

        // Verify child's display state was updated
        let updatedChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(updatedChild.displayState == 1)
    }

    @Test func addGroupMultipleChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        // Create multiple child items
        let child1Item = await root.itemController.addNew(type: nil)
        let child1 = await root.itemController.itemOrEmpty(for: child1Item.itemId)

        let child2Item = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item.itemId)

        // Set current item to parent
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add first child
        await sut.addGroup(childId: child1.id)
        #expect(await sut.model.entries.count == 1)

        // Add second child
        await sut.addGroup(childId: child2.id)
        #expect(await sut.model.entries.count == 2)
        #expect(parent.entries.count == 2)

        // Verify both children are in the group
        let childIds = parent.entries.map { $0.spaceId }
        #expect(childIds.contains(child1.id))
        #expect(childIds.contains(child2.id))
    }

    @Test func addGroupIgnoresSameId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to add parent to itself - should be ignored
        await sut.addGroup(childId: parent.id)

        #expect(await sut.model.entries.count == 0)
        #expect(parent.entries.count == 0)
    }

    @Test func addGroupIgnoresDuplicateEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent and child items
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        let childItem = await root.itemController.addNew(type: nil)
        let child = await root.itemController.itemOrEmpty(for: childItem.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add child first time
        await sut.addGroup(childId: child.id)
        #expect(await sut.model.entries.count == 1)

        // Try to add same child again - should be ignored
        await sut.addGroup(childId: child.id)
        #expect(await sut.model.entries.count == 1)
        #expect(parent.entries.count == 1)
    }

    @Test func removeGroup() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent and child items
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        let childItem = await root.itemController.addNew(type: nil)
        let child = await root.itemController.itemOrEmpty(for: childItem.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add child to group
        await sut.addGroup(childId: child.id)
        #expect(await sut.model.entries.count == 1)
        let updatedChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(updatedChild.displayState == 1)

        // Remove child from group
        await sut.removeGroup(childId: child.id)

        #expect(await sut.model.entries.count == 0)
        #expect(parent.entries.count == 0)

        // Verify child's display state was reset
        let finalChild = await root.itemController.itemOrEmpty(for: child.id)
        #expect(finalChild.displayState == 0)
    }

    @Test func removeGroupFromMultiple() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent and multiple child items
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        let child1Item = await root.itemController.addNew(type: nil)
        let child1 = await root.itemController.itemOrEmpty(for: child1Item.itemId)

        let child2Item = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item.itemId)

        let child3Item = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.itemOrEmpty(for: child3Item.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add all children
        await sut.addGroup(childId: child1.id)
        await sut.addGroup(childId: child2.id)
        await sut.addGroup(childId: child3.id)
        #expect(await sut.model.entries.count == 3)

        // Remove middle child
        await sut.removeGroup(childId: child2.id)

        #expect(await sut.model.entries.count == 2)
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
        let sut = root.editController

        // Create parent item
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Try to remove parent from itself - should be ignored
        await sut.removeGroup(childId: parent.id)

        #expect(await sut.model.entries.count == 0)
        #expect(parent.entries.count == 0)
    }

    @Test func removeGroupNonExistentChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent and children
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        let child1Item = await root.itemController.addNew(type: nil)
        let child1 = await root.itemController.itemOrEmpty(for: child1Item.itemId)

        let child2Item = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.itemOrEmpty(for: child2Item.itemId)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))

        // Add only child1 to group
        await sut.addGroup(childId: child1.id)
        #expect(await sut.model.entries.count == 1)

        // Try to remove child2 (not in group) - should have no effect
        await sut.removeGroup(childId: child2.id)

        #expect(await sut.model.entries.count == 1)
        #expect(parent.entries.count == 1)
        #expect(parent.entries[0].spaceId == child1.id)
    }

    @Test func addItemToFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create a regular item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)
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
        let sut = root.editController

        // Create a collection (album for spaces)
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create a regular item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)

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
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create multiple items
        let item1 = await root.itemController.addNew(type: nil)
        let item2 = await root.itemController.addNew(type: nil)
        let item3 = await root.itemController.addNew(type: nil)

        // Add all items to folder
        await sut.addItem(itemId: item1.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: item2.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: item3.itemId, parentId: folderModel.id)

        // Verify all items were added
        let updatedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(updatedFolder.entries.count == 3)

        let entryIds = updatedFolder.entries.map { $0.spaceId }
        #expect(entryIds.contains(item1.itemId))
        #expect(entryIds.contains(item2.itemId))
        #expect(entryIds.contains(item3.itemId))

        // Verify all items have the correct parentId
        #expect(await root.itemController.itemOrEmpty(for: item1.itemId).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: item2.itemId).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: item3.itemId).parentId == folderModel.id)
    }

    @Test func addItemToFolderIgnoresSameId() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Try to add folder to itself
        await sut.addItem(itemId: folderModel.id, parentId: folderModel.id)

        // Should have no entries (cannot add to itself)
        let updatedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(updatedFolder.entries.count == 0)
    }

    @Test func addItemToFolderIgnoresDuplicateParent() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)

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
        let sut = root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create a folder (special category)
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Try to add folder to collection - should be ignored (special category can't be in non-folder)
        await sut.addItem(itemId: folderModel.id, parentId: collectionModel.id)

        let updatedCollection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(updatedCollection.entries.count == 0)
    }

    @Test func addItemToFolderAllowsSpecialCategory() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create parent folder
        let parentFolderModel = SpaceModel(id: UUID(), name: "Parent Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: parentFolderModel, isInsert: true, shouldRepairLinks: true)

        // Create child folder (special category)
        let childFolderModel = SpaceModel(id: UUID(), name: "Child Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: childFolderModel, isInsert: true, shouldRepairLinks: true)

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
        let sut = root.editController

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)

        // Try to add item with nil parentId - should be ignored
        await sut.addItem(itemId: item.id, parentId: nil)

        // Item should remain unchanged
        let updatedItem = await root.itemController.itemOrEmpty(for: item.id)
        #expect(updatedItem.parentId == nil)
    }

    @Test func addNewItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

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
        let sut = root.editController

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
        let sut = root.editController

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
        let sut = root.editController

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)
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
        let sut = root.editController

        // Create a parent item
        let parentItem = await root.itemController.addNew(type: nil)
        let parent = await root.itemController.itemOrEmpty(for: parentItem.itemId)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)

        // Add children to parent using addGroup
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: parent.id, typeId: .space))
        await sut.addGroup(childId: child1.itemId)
        await sut.addGroup(childId: child2.itemId)

        let updatedParent = await root.itemController.itemOrEmpty(for: parent.id)
        #expect(updatedParent.entries.count == 2)
        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).displayState == 1)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).displayState == 1)

        // Delete the parent
        await sut.delete(itemId: parent.id)

        // Verify parent is marked for deletion
        let deletedParent = await root.itemController.itemOrEmpty(for: parent.id)
        #expect(deletedParent.displayState == 2)

        // Verify children's displayState is reset to 0
        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).displayState == 0)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).displayState == 0)
    }

    @Test func deleteFolderWithChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)

        // Add children to folder
        await sut.addItem(itemId: child1.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: folderModel.id)

        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).parentId == folderModel.id)

        // Delete the folder
        await sut.delete(itemId: folderModel.id)

        // Verify folder is marked for deletion
        let deletedFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(deletedFolder.displayState == 2)

        // Verify children's parentId is reset to nil (moved to parent's parent, which is nil)
        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).parentId == nil)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).parentId == nil)
    }

    @Test func duplicate() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))
        await sut.reset(name: "Original Item")

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
        let sut = root.editController

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)
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
        let sut = root.editController

        // Create an item
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId)

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
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)

        // Add children to folder
        await sut.addItem(itemId: child1.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: folderModel.id)

        // Delete the folder (which affects children)
        await sut.delete(itemId: folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: folderModel.id).displayState == 2)

        // Restore the folder
        await sut.restore(itemId: folderModel.id)

        // Verify folder is restored
        let restoredFolder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(restoredFolder.displayState == 0)

        // Verify children's parentId is set back to folder and displayState is hidden (1)
        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).parentId == folderModel.id)
        #expect(await root.itemController.itemOrEmpty(for: child1.itemId).displayState == 1)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).displayState == 1)
    }

    @Test func removeItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.addNew(type: nil)

        // Add children to collection
        await sut.addItem(itemId: child1.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child3.itemId, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // Remove the middle entry (index 1)
        await sut.removeItem(offsets: IndexSet(integer: 1), item: collection)

        // Verify entry was removed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 2)

        let entryIds = collection.entries.map { $0.spaceId }
        #expect(entryIds.contains(child1.itemId))
        #expect(!entryIds.contains(child2.itemId))
        #expect(entryIds.contains(child3.itemId))

        // For collection, child should NOT be deleted (displayState still 0)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).displayState == 0)
    }

    @Test func removeItemFromFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a folder
        let folderModel = SpaceModel(id: UUID(), name: "Test Folder", category: .folder, displayState: 0)
        await root.itemController.replace(model: folderModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.addNew(type: nil)

        // Add children to folder
        await sut.addItem(itemId: child1.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: folderModel.id)
        await sut.addItem(itemId: child3.itemId, parentId: folderModel.id)

        var folder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder.entries.count == 3)

        // Remove the middle entry (index 1) from folder
        await sut.removeItem(offsets: IndexSet(integer: 1), item: folder)

        // Verify entry was removed
        folder = await root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(folder.entries.count == 2)

        // For folder, removed child should be deleted (displayState = 2)
        #expect(await root.itemController.itemOrEmpty(for: child2.itemId).displayState == 2)
    }

    @Test func removeMultipleItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.addNew(type: nil)
        let child4 = await root.itemController.addNew(type: nil)

        // Add children to collection
        await sut.addItem(itemId: child1.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child3.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child4.itemId, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // Remove multiple entries (indices 1 and 2)
        await sut.removeItem(offsets: IndexSet([1, 2]), item: collection)

        // Verify entries were removed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 2)

        let entryIds = collection.entries.map { $0.spaceId }
        #expect(entryIds.contains(child1.itemId))
        #expect(!entryIds.contains(child2.itemId))
        #expect(!entryIds.contains(child3.itemId))
        #expect(entryIds.contains(child4.itemId))
    }

    @Test func moveItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.addNew(type: nil)

        // Add children to collection
        await sut.addItem(itemId: child1.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child3.itemId, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // Original order: child1, child2, child3
        #expect(collection.entries[0].spaceId == child1.itemId)
        #expect(collection.entries[1].spaceId == child2.itemId)
        #expect(collection.entries[2].spaceId == child3.itemId)

        // Move first item (index 0) to position 2 (after child2)
        await sut.moveItems(source: IndexSet(integer: 0), destination: 2, item: collection)

        // Verify order changed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 3)

        // New order should be: child2, child1, child3
        #expect(collection.entries[0].spaceId == child2.itemId)
        #expect(collection.entries[1].spaceId == child1.itemId)
        #expect(collection.entries[2].spaceId == child3.itemId)
    }

    @Test func moveMultipleItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController

        // Create a collection
        let collectionModel = SpaceModel(id: UUID(), name: "Test Collection", category: .album, displayState: 0)
        await root.itemController.replace(model: collectionModel, isInsert: true, shouldRepairLinks: true)

        // Create children
        let child1 = await root.itemController.addNew(type: nil)
        let child2 = await root.itemController.addNew(type: nil)
        let child3 = await root.itemController.addNew(type: nil)
        let child4 = await root.itemController.addNew(type: nil)

        // Add children to collection
        await sut.addItem(itemId: child1.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child2.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child3.itemId, parentId: collectionModel.id)
        await sut.addItem(itemId: child4.itemId, parentId: collectionModel.id)

        var collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // Original order: child1, child2, child3, child4
        #expect(collection.entries[0].spaceId == child1.itemId)
        #expect(collection.entries[1].spaceId == child2.itemId)
        #expect(collection.entries[2].spaceId == child3.itemId)
        #expect(collection.entries[3].spaceId == child4.itemId)

        // Move items at indices 0 and 1 (child1, child2) to position 3
        await sut.moveItems(source: IndexSet([0, 1]), destination: 3, item: collection)

        // Verify order changed
        collection = await root.itemController.itemOrEmpty(for: collectionModel.id)
        #expect(collection.entries.count == 4)

        // New order should be: child3, child1, child2, child4
        #expect(collection.entries[0].spaceId == child3.itemId)
        #expect(collection.entries[1].spaceId == child1.itemId)
        #expect(collection.entries[2].spaceId == child2.itemId)
        #expect(collection.entries[3].spaceId == child4.itemId)
    }
}
