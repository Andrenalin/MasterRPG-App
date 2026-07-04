// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

/// Tests for ConvertController.repairHiddenAndFolders function
/// Following Swift Testing best practices with Arrange-Act-Assert pattern
@Suite("ConvertController repairHiddenAndFolders Tests")
@MainActor
struct ConvertControllerRepairTests {

    // MARK: - Folder Cleaning Tests

    @Test("Clean folder removes entries with mismatched parentId")
    func cleanFolder_removesInvalidEntries() async throws {
        // Given - A folder with entries where children have incorrect parentId
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create a folder
        let folderId = await root.editController.addNew(type: .folder)
        try #require(folderId != nil)
        guard let folderModel = folderId else { return }
        root.editController.reset(name: "TestFolder", itemId: folderModel.id)

        // Create two child items
        let child1Id = await root.editController.addNew(type: .item)
        let child2Id = await root.editController.addNew(type: .item)
        try #require(child1Id != nil)
        try #require(child2Id != nil)
        guard let child1 = child1Id, let child2 = child2Id else { return }

        root.editController.reset(name: "Child1", itemId: child1.id)
        root.editController.reset(name: "Child2", itemId: child2.id)

        // Add children to folder
        root.editController.addItem(itemId: child1.id, parentId: folderModel.id)
        root.editController.addItem(itemId: child2.id, parentId: folderModel.id)

        // Manually corrupt child2's parentId (simulate data inconsistency)
        let corruptedChild2 = root.itemController.itemOrEmpty(for: child2.id)
        corruptedChild2.parentId = nil
        root.itemController.replace(model: corruptedChild2, isInsert: false)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Folder should have only valid entries
        let repairedFolder = root.itemController.itemOrEmpty(for: folderModel.id)
        #expect(repairedFolder.entries.count == 1)
        #expect(repairedFolder.entries[0].childId == child1.id)
    }

    // MARK: - Hidden State Reset Tests

    @Test("Reset hidden state for root items with displayState 1")
    func resetHidden_forRootItemsWithDisplayState1() async throws {
        // Given - A root item with displayState == 1 and no parent
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "HiddenItem", itemId: item.id)
        root.editController.reset(displayState: 1, itemId: item.id)

        // Verify initial state
        let itemBefore = root.itemController.itemOrEmpty(for: item.id)
        #expect(itemBefore.displayState == 1)
        #expect(itemBefore.parentId == nil)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Item should have isGroupHiddenToggle set to false (visible)
        let itemAfter = root.itemController.itemOrEmpty(for: item.id)
        #expect(itemAfter.isGroupHiddenToggle == false)
    }

    @Test("Do not reset hidden state for items with parent")
    func resetHidden_skipsItemsWithParent() async throws {
        // Given - An item with displayState == 1 but has a parent
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.editController.addNew(type: .folder)
        let childId = await root.editController.addNew(type: .item)
        try #require(folderId != nil)
        try #require(childId != nil)
        guard let folder = folderId, let child = childId else { return }

        root.editController.reset(name: "Folder", itemId: folder.id)
        root.editController.reset(name: "Child", itemId: child.id)
        root.editController.addItem(itemId: child.id, parentId: folder.id)
        root.editController.reset(displayState: 1, itemId: child.id)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Child should still have displayState == 1 (not reset)
        let childAfter = root.itemController.itemOrEmpty(for: child.id)
        #expect(childAfter.displayState == 1)
        #expect(childAfter.parentId == folder.id)
    }

    // MARK: - Category Conversion Tests

    @Test("Convert non-entry non-special category to entry with tag")
    func convertCategory_toEntryWithTag() async throws {
        // Given - An item with a non-special, non-entry category
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "TestItem", itemId: item.id)
        root.editController.reset(category: .photo, itemId: item.id)
        root.editController.reset(tags: ["ExistingTag"], itemId: item.id)

        // Verify initial state
        let itemBefore = root.itemController.itemOrEmpty(for: item.id)
        #expect(itemBefore.category == .photo)
        #expect(itemBefore.tags.count == 1)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Category should be .entry and original category added as tag
        let itemAfter = root.itemController.itemOrEmpty(for: item.id)
        #expect(itemAfter.category == .entry)
        #expect(itemAfter.tags.contains("Photo"))
        #expect(itemAfter.tags.contains("ExistingTag"))
    }

    @Test("Skip conversion for special categories (folder, collection)")
    func convertCategory_skipsSpecialCategories() async throws {
        // Given - Items with special categories
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let folderId = await root.editController.addNew(type: .folder)
        try #require(folderId != nil)
        guard let folder = folderId else { return }

        root.editController.reset(name: "TestFolder", itemId: folder.id)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Folder should remain as folder
        let folderAfter = root.itemController.itemOrEmpty(for: folder.id)
        #expect(folderAfter.category == .folder)
    }

    @Test("Skip conversion for entry category")
    func convertCategory_skipsEntryCategory() async throws {
        // Given - An item already with .entry category
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "TestItem", itemId: item.id)
        root.editController.reset(category: .entry, itemId: item.id)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Category should remain .entry with no extra tags
        let itemAfter = root.itemController.itemOrEmpty(for: item.id)
        #expect(itemAfter.category == .entry)
    }

    // MARK: - Folder Path Extraction Tests

    @Test("Extract folder path and create folder hierarchy")
    func extractFolderPath_createsFolderHierarchy() async throws {
        // Given - An item with a file URL containing folder structure
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "TestFile", itemId: item.id)

        // Set file URL with folder structure
        let updatedItem = root.itemController.itemOrEmpty(for: item.id)
        updatedItem.fileUrl = FileUrl(
            fileId: item.id,
            url: URL(filePath: "/RootFolder/SubFolder/TestFile.txt"),
            location: .other,
            module: "Test",
            relativeUrl: nil
        )
        root.itemController.replace(model: updatedItem, isInsert: false)

        let initialItemCount = root.itemController.itemDataModel.items.count
        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Folder hierarchy should be created
        let finalItemCount = root.itemController.itemDataModel.items.count
        #expect(finalItemCount > initialItemCount)

        // Find the created folders
        var rootFolder: SpaceModel?
        var subFolder: SpaceModel?

        for itemId in root.itemController.itemDataModel.items {
            let model = root.itemController.itemOrEmpty(for: itemId)
            if model.name == "RootFolder" && model.category == .folder {
                rootFolder = model
            }
            if model.name == "SubFolder" && model.category == .folder {
                subFolder = model
            }
        }

        try #require(rootFolder != nil)
        try #require(subFolder != nil)

        // Verify folder hierarchy
        #expect(rootFolder?.parentId == nil)
        #expect(subFolder?.parentId == rootFolder?.id)

        // Verify the item is now in the subfolder
        let finalItem = root.itemController.itemOrEmpty(for: item.id)
        #expect(finalItem.parentId == subFolder?.id)
    }

    @Test("Skip folder extraction for items without URLs")
    func extractFolderPath_skipsItemsWithoutUrl() async throws {
        // Given - An item without a file URL
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "NoUrlItem", itemId: item.id)

        let initialItemCount = root.itemController.itemDataModel.items.count
        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - No new folders should be created
        let finalItemCount = root.itemController.itemDataModel.items.count
        #expect(finalItemCount == initialItemCount)
    }

    // MARK: - Orphaned Folder Repair Tests

    @Test("Repair orphaned folder - reset parentId to nil when not in parent entries")
    func repairOrphanedFolder_resetsParentIdToNil() async throws {
        // Given - A folder with parentId set, but parent doesn't contain it in entries
        // This simulates import with overwrite where children were replaced
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create parent folder
        let parentId = await root.editController.addNew(type: .folder)
        try #require(parentId != nil)
        guard let parent = parentId else { return }
        root.editController.reset(name: "ParentFolder", itemId: parent.id)

        // Create orphaned folder with parentId but not in parent's entries
        let orphanedId = await root.editController.addNew(type: .folder)
        try #require(orphanedId != nil)
        guard let orphaned = orphanedId else { return }
        root.editController.reset(name: "OrphanedFolder", itemId: orphaned.id)

        // Manually set parentId without adding to parent's entries (simulate corruption)
        let orphanedModel = root.itemController.itemOrEmpty(for: orphaned.id)
        orphanedModel.parentId = parent.id
        root.itemController.replace(model: orphanedModel, isInsert: false)

        // Verify orphaned state
        let orphanedBefore = root.itemController.itemOrEmpty(for: orphaned.id)
        #expect(orphanedBefore.parentId == parent.id)
        let parentBefore = root.itemController.itemOrEmpty(for: parent.id)
        #expect(parentBefore.entries.isEmpty)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Orphaned folder should be reset to root level
        let orphanedAfter = root.itemController.itemOrEmpty(for: orphaned.id)
        #expect(orphanedAfter.parentId == nil)
    }

    @Test("Repair multiple orphaned folders at same level")
    func repairOrphanedFolders_multipleAtSameLevel() async throws {
        // Given - Multiple folders orphaned from the same parent
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create parent folder
        let parentId = await root.editController.addNew(type: .folder)
        try #require(parentId != nil)
        guard let parent = parentId else { return }
        root.editController.reset(name: "ParentFolder", itemId: parent.id)

        // Create three orphaned folders
        let orphaned1Id = await root.editController.addNew(type: .folder)
        let orphaned2Id = await root.editController.addNew(type: .folder)
        let orphaned3Id = await root.editController.addNew(type: .folder)
        try #require(orphaned1Id != nil)
        try #require(orphaned2Id != nil)
        try #require(orphaned3Id != nil)
        guard let orphaned1 = orphaned1Id,
              let orphaned2 = orphaned2Id,
              let orphaned3 = orphaned3Id else { return }

        root.editController.reset(name: "Orphaned1", itemId: orphaned1.id)
        root.editController.reset(name: "Orphaned2", itemId: orphaned2.id)
        root.editController.reset(name: "Orphaned3", itemId: orphaned3.id)

        // Set all as orphaned
        for orphanedId in [orphaned1, orphaned2, orphaned3] {
            let model = root.itemController.itemOrEmpty(for: orphanedId.id)
            model.parentId = parent.id
            root.itemController.replace(model: model, isInsert: false)
        }

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - All orphaned folders should be at root level
        let orphaned1After = root.itemController.itemOrEmpty(for: orphaned1.id)
        let orphaned2After = root.itemController.itemOrEmpty(for: orphaned2.id)
        let orphaned3After = root.itemController.itemOrEmpty(for: orphaned3.id)

        #expect(orphaned1After.parentId == nil)
        #expect(orphaned2After.parentId == nil)
        #expect(orphaned3After.parentId == nil)
    }

    @Test("Repair nested orphaned folders - grandchild orphaned from parent")
    func repairOrphanedFolder_nestedHierarchy() async throws {
        // Given - A nested folder structure where a grandchild is orphaned
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create hierarchy: Root -> Parent -> Child (but Child not in Parent's entries)
        let rootFolderId = await root.editController.addNew(type: .folder)
        let parentFolderId = await root.editController.addNew(type: .folder)
        let childFolderId = await root.editController.addNew(type: .folder)
        try #require(rootFolderId != nil)
        try #require(parentFolderId != nil)
        try #require(childFolderId != nil)
        guard let rootFolder = rootFolderId,
              let parentFolder = parentFolderId,
              let childFolder = childFolderId else { return }

        root.editController.reset(name: "RootFolder", itemId: rootFolder.id)
        root.editController.reset(name: "ParentFolder", itemId: parentFolder.id)
        root.editController.reset(name: "ChildFolder", itemId: childFolder.id)

        // Properly link rootFolder -> parentFolder
        root.editController.addItem(itemId: parentFolder.id, parentId: rootFolder.id)

        // Orphan childFolder (has parentId but not in parent's entries)
        let childModel = root.itemController.itemOrEmpty(for: childFolder.id)
        childModel.parentId = parentFolder.id
        root.itemController.replace(model: childModel, isInsert: false)

        // Verify orphaned state
        let childBefore = root.itemController.itemOrEmpty(for: childFolder.id)
        #expect(childBefore.parentId == parentFolder.id)
        let parentBefore = root.itemController.itemOrEmpty(for: parentFolder.id)
        #expect(parentBefore.entries.isEmpty)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Child folder should be reset to root level
        let childAfter = root.itemController.itemOrEmpty(for: childFolder.id)
        #expect(childAfter.parentId == nil)

        // Parent and root should remain unchanged
        let parentAfter = root.itemController.itemOrEmpty(for: parentFolder.id)
        let rootAfter = root.itemController.itemOrEmpty(for: rootFolder.id)
        #expect(parentAfter.parentId == rootFolder.id)
        #expect(rootAfter.parentId == nil)
    }

    @Test("Repair orphaned items - not just folders")
    func repairOrphanedItem_resetsParentIdToNil() async throws {
        // Given - An item (not folder) with parentId but not in parent's entries
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create parent folder
        let parentId = await root.editController.addNew(type: .folder)
        try #require(parentId != nil)
        guard let parent = parentId else { return }
        root.editController.reset(name: "ParentFolder", itemId: parent.id)

        // Create orphaned item
        let orphanedItemId = await root.editController.addNew(type: .item)
        try #require(orphanedItemId != nil)
        guard let orphanedItem = orphanedItemId else { return }
        root.editController.reset(name: "OrphanedItem", itemId: orphanedItem.id)

        // Manually set parentId without adding to parent's entries
        let orphanedModel = root.itemController.itemOrEmpty(for: orphanedItem.id)
        orphanedModel.parentId = parent.id
        root.itemController.replace(model: orphanedModel, isInsert: false)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Orphaned item should be reset to root level
        let orphanedAfter = root.itemController.itemOrEmpty(for: orphanedItem.id)
        #expect(orphanedAfter.parentId == nil)
    }

    @Test("Do not repair valid folders - parent contains child in entries")
    func repairOrphanedFolder_skipsValidFolders() async throws {
        // Given - A valid folder hierarchy where parent contains child in entries
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create valid parent-child relationship
        let parentId = await root.editController.addNew(type: .folder)
        let childId = await root.editController.addNew(type: .folder)
        try #require(parentId != nil)
        try #require(childId != nil)
        guard let parent = parentId, let child = childId else { return }

        root.editController.reset(name: "ParentFolder", itemId: parent.id)
        root.editController.reset(name: "ChildFolder", itemId: child.id)
        root.editController.addItem(itemId: child.id, parentId: parent.id)

        // Verify valid state
        let childBefore = root.itemController.itemOrEmpty(for: child.id)
        #expect(childBefore.parentId == parent.id)
        let parentBefore = root.itemController.itemOrEmpty(for: parent.id)
        #expect(parentBefore.entries.count == 1)
        #expect(parentBefore.entries[0].childId == child.id)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Valid relationship should remain unchanged
        let childAfter = root.itemController.itemOrEmpty(for: child.id)
        let parentAfter = root.itemController.itemOrEmpty(for: parent.id)

        #expect(childAfter.parentId == parent.id)
        #expect(parentAfter.entries.count == 1)
        #expect(parentAfter.entries[0].childId == child.id)
    }

    @Test("Repair mixed scenario - some orphaned, some valid")
    func repairOrphanedFolder_mixedScenario() async throws {
        // Given - A parent with both valid and orphaned children
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create parent folder
        let parentId = await root.editController.addNew(type: .folder)
        try #require(parentId != nil)
        guard let parent = parentId else { return }
        root.editController.reset(name: "ParentFolder", itemId: parent.id)

        // Create valid child (properly linked)
        let validChildId = await root.editController.addNew(type: .folder)
        try #require(validChildId != nil)
        guard let validChild = validChildId else { return }
        root.editController.reset(name: "ValidChild", itemId: validChild.id)
        root.editController.addItem(itemId: validChild.id, parentId: parent.id)

        // Create orphaned child (has parentId but not in entries)
        let orphanedChildId = await root.editController.addNew(type: .folder)
        try #require(orphanedChildId != nil)
        guard let orphanedChild = orphanedChildId else { return }
        root.editController.reset(name: "OrphanedChild", itemId: orphanedChild.id)

        let orphanedModel = root.itemController.itemOrEmpty(for: orphanedChild.id)
        orphanedModel.parentId = parent.id
        root.itemController.replace(model: orphanedModel, isInsert: false)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Valid child remains linked, orphaned child reset to root
        let validChildAfter = root.itemController.itemOrEmpty(for: validChild.id)
        let orphanedChildAfter = root.itemController.itemOrEmpty(for: orphanedChild.id)
        let parentAfter = root.itemController.itemOrEmpty(for: parent.id)

        #expect(validChildAfter.parentId == parent.id)
        #expect(orphanedChildAfter.parentId == nil)
        #expect(parentAfter.entries.count == 1)
        #expect(parentAfter.entries[0].childId == validChild.id)
    }

    // MARK: - Integration Tests

    @Test("Repair performs all operations in correct sequence")
    func repairHiddenAndFolders_performsAllOperations() async throws {
        // Given - Multiple items requiring different repairs
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        // Create a folder with entries
        let folderId = await root.editController.addNew(type: .folder)
        try #require(folderId != nil)
        guard let folder = folderId else { return }
        root.editController.reset(name: "Folder", itemId: folder.id)

        // Create an item with wrong category and hidden state
        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "Item", itemId: item.id)
        root.editController.reset(category: .photo, itemId: item.id)
        root.editController.reset(displayState: 1, itemId: item.id)

        let reportModel = ValidateRepairModel()

        // When - Run repairHiddenAndFolders
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - All repairs should be applied
        let repairedFolder = root.itemController.itemOrEmpty(for: folder.id)
        #expect(repairedFolder.category == .folder)

        let repairedItem = root.itemController.itemOrEmpty(for: item.id)
        #expect(repairedItem.category == .entry)
        #expect(repairedItem.tags.contains("Photo"))
        #expect(repairedItem.isGroupHiddenToggle == false)
    }

    @Test("Repair is idempotent - running twice produces same result")
    func repairHiddenAndFolders_isIdempotent() async throws {
        // Given - Items that need repair
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let itemId = await root.editController.addNew(type: .item)
        try #require(itemId != nil)
        guard let item = itemId else { return }

        root.editController.reset(name: "Item", itemId: item.id)
        root.editController.reset(category: .photo, itemId: item.id)

        let reportModel = ValidateRepairModel()

        // When - Run repair twice
        await sut.repairHiddenAndFolders(reportModel: reportModel)
        let afterFirstRun = root.itemController.itemOrEmpty(for: item.id)

        await sut.repairHiddenAndFolders(reportModel: reportModel)
        let afterSecondRun = root.itemController.itemOrEmpty(for: item.id)

        // Then - Results should be identical
        #expect(afterFirstRun.category == afterSecondRun.category)
        #expect(afterFirstRun.tags == afterSecondRun.tags)
        #expect(afterFirstRun.displayState == afterSecondRun.displayState)
    }

    @Test("Repair handles empty item list gracefully")
    func repairHiddenAndFolders_handlesEmptyList() async throws {
        // Given - An empty root with no items
        let root = SpaceRootModel.testRoot()
        let sut = ConvertController(
            itemController: root.itemController,
            editController: root.editController
        )

        let reportModel = ValidateRepairModel()

        // When - Run repair on empty list
        await sut.repairHiddenAndFolders(reportModel: reportModel)

        // Then - Should complete without errors
        let itemCount = root.itemController.itemDataModel.items.count
        #expect(itemCount == 0)
    }
}
