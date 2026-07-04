// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import DiceRPG

@MainActor
struct ItemControllerTests {
    @Test func addNewItem() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Act
        let itemId = await sut.addNew(type: .item)
        
        // Assert
        // Check that the new item was created
        let item = await sut.item(for: itemId)
        #expect(item != nil, "New item should exist")
        
        // Check that the item has the correct category
        if let item = item {
            #expect(item.category == .item, "Item should have the correct category")
        }
        
        // Check that the item was added to the data model
        let items = sut.itemDataModel.items
        #expect(items.contains(itemId), "Item should be in the data model")
    }
    
    @Test func addNewFolder() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Act
        let itemId = await sut.addNew(type: .folder)
        
        // Assert
        // Check that the new folder was created
        let item = await sut.item(for: itemId)
        #expect(item != nil, "New folder should exist")
        
        // Check that the folder has the correct category
        if let item = item {
            #expect(item.category == .folder, "Item should have folder category")
        }
    }
    
    @Test func copyOfItem() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Create a test item
        let itemId = await sut.addNew(type: .item)
        
        // Act
        let copiedItem = sut.copy(of: itemId)
        
        // Assert
        #expect(copiedItem != nil, "Copy should return a non-nil item")
        
        if let copiedItem, let originalItem = await sut.item(for: itemId) {
            // Copy should have same ID but should not be identical instance
            #expect(copiedItem.id == originalItem.id, "Copy should have the same ID")
            #expect(copiedItem !== originalItem as AnyObject, "Copy should be a new instance")
            
            // Copy should have same properties
            #expect(copiedItem.name == originalItem.name, "Copy should have same name")
            #expect(copiedItem.category == originalItem.category, "Copy should have same category")
            #expect(copiedItem.description == originalItem.description, "Copy should have same description")
        }
    }
    
    @Test func deleteItem() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Create a test item
        let itemId = await sut.addNew(type: .item)
        let initialItemCount = sut.itemDataModel.items.count
        
        // Verify item exists before deletion
        let itemBeforeDelete = await sut.item(for: itemId)
        #expect(itemBeforeDelete != nil, "Item should exist before deletion")
        
        // Act
        await sut.delete(itemId: itemId)
        
        // Assert
        // Check that item no longer exists
        let itemAfterDelete = await sut.item(for: itemId)
        #expect(itemAfterDelete == nil, "Item should not exist after deletion")
        
        // Check that item was removed from data model
        let finalItemCount = sut.itemDataModel.items.count
        #expect(finalItemCount == initialItemCount - 1, "Item count should be decreased by 1")
    }
    
    @Test func isEqualWithSameItem() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Create a test item
        let itemId = await sut.addNew(type: .item)
        
        // Get the item and a copy of it
        let item = await sut.item(for: itemId)
        let copy = sut.copy(of: itemId)
        
        #expect(item != nil && copy != nil, "Both item and copy should exist")
        
        // Act
        if let copy {
            let isEqual = sut.isEqual(with: copy)
            
            // Assert
            #expect(isEqual == true, "Item should be equal to its copy")
        }
    }
    
    @Test func isEqualWithDifferentItems() async throws {
        // Arrange
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        // Create two different items
        let itemId1 = await sut.addNew(type: .item)
        let itemId2 = await sut.addNew(type: .item)
        
        // Get the second item
        let secondItem = await sut.item(for: itemId2)
        #expect(secondItem != nil, "Second item should exist")
        
        // Act - compare first item with modified copy of second item
        if let secondItem {
            // Create a modified copy with the first item's ID to test isEqual
            let modifiedCopy = secondItem.copy(withId: itemId1)
            
            let isEqual = sut.isEqual(with: modifiedCopy)
            
            // Assert
            #expect(isEqual == false, "Different items should not be equal")
        }
    }
}
