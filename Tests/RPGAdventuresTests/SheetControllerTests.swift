// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG

@MainActor
struct SheetControllerTests {
    @Test func adventureSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == .item)
        #expect(model.source.itemId == itemId)
        #expect(!model.name.isEmpty)
    }

    @Test func adventureSheetWithPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        if item.photoId != nil {
            let photoEntry = model.inlineEntries.first(where: { $0.sheetType == SheetModelType.photo })
            #expect(photoEntry != nil)
            #expect(photoEntry?.level == 0)
        }
    }

    @Test func adventureSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count >= 0)
        for entry in model.entries where entry.sheetType != SheetModelType.photo {
            #expect(entry.source.entryId != nil)
            #expect(entry.level == 0)
        }
    }

    @Test func adventureSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let entries = sut.sheetEntries(root: root.rootManager!, itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false) // Links default to hidden
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func adventureSheetLinkToAdventureModule() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let entries = sut.sheetEntries(root: root.rootManager!, itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            for link in entry.entries where link.source.typeId == NetworkModules.adventure {
                #expect(link.level == 1)
                #expect(link.isShown == false)
            }
        }
    }

    @Test func adventureSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let modelShown = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func adventureSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        // Test isFolded at moduleDepth >= 4
        let modelFolded = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 4, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 3, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func adventureSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.adventure)
        let model = sut.sheet(root: root.rootManager!, itemId: itemId!, destination: destination, level: 0, isShown: true, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
    }

    @Test func searchPreservesIsShownState() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        // Set initial isShown states
        if rootModel.sheetModel.entries.count > 0 {
            rootModel.sheetModel.entries[0].isShown = true
        }
        if rootModel.sheetModel.entries.count > 1 {
            rootModel.sheetModel.entries[1].isShown = false
        }

        let initialStates = rootModel.sheetModel.entries.map { $0.isShown }

        // Start search
        rootModel.searchText = "test"

        // Verify isShown states are preserved during search
        for (index, entry) in rootModel.sheetModel.entries.enumerated() {
            #expect(entry.isShown == initialStates[index], "isShown state changed during search for entry \(index)")
        }

        // Clear search
        rootModel.searchText = ""

        // Verify isShown states are restored after clearing search
        for (index, entry) in rootModel.sheetModel.entries.enumerated() {
            #expect(entry.isShown == initialStates[index], "isShown state not restored after clearing search for entry \(index)")
        }
    }

    @Test func searchDoesNotRestoreOnInitialization() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        // Create model - searchText is "" by default
        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        // Verify that initial states are preserved (not overwritten by empty search)
        for entry in rootModel.sheetModel.entries {
            // The state should match whatever was set during initialization, not forced to false
            #expect(entry.isHidden == false, "Entries should not be hidden on initialization")
        }
    }

    @Test func searchRestoresStateOnlyAfterActiveSearch() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        // Set initial states
        if rootModel.sheetModel.entries.count > 0 {
            rootModel.sheetModel.entries[0].isShown = true
        }
        if rootModel.sheetModel.entries.count > 1 {
            rootModel.sheetModel.entries[1].isShown = false
        }

        let initialStates = rootModel.sheetModel.entries.map { $0.isShown }

        // Set searchText to empty (should not trigger restore since no active search)
        rootModel.searchText = ""

        // Verify states unchanged
        for (index, entry) in rootModel.sheetModel.entries.enumerated() {
            #expect(entry.isShown == initialStates[index], "State should not change when setting empty searchText without active search")
        }

        // Now do an actual search
        rootModel.searchText = "adventure"
        rootModel.searchText = ""

        // Now it should restore
        for (index, entry) in rootModel.sheetModel.entries.enumerated() {
            #expect(entry.isShown == initialStates[index], "State should be restored after active search is cleared")
        }
    }

    @Test func moveEntryPreservesIsShownState() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        guard rootModel.sheetModel.entries.count >= 2 else {
            return // Skip test if not enough entries
        }

        // Set initial states
        rootModel.sheetModel.entries[0].isShown = true
        rootModel.sheetModel.entries[1].isShown = false

        let entry0 = rootModel.sheetModel.entries[0]
        let entry1 = rootModel.sheetModel.entries[1]

        // Move entry down (should not affect isShown)
        rootModel.moveEntry(entryModel: entry0, in: rootModel.sheetModel, up: false)

        // Verify states preserved after move
        #expect(entry0.isShown == true, "First entry isShown should remain true after move")
        #expect(entry1.isShown == false, "Second entry isShown should remain false after move")
    }

    @Test func searchExpandsParentWhenChildMatches() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        // Find an entry with children
        var parentEntry: SheetModel?
        for entry in rootModel.sheetModel.entries {
            if !entry.entries.isEmpty {
                parentEntry = entry
                break
            }
        }

        guard let parent = parentEntry, !parent.entries.isEmpty else {
            // Skip test if no suitable entry found
            return
        }

        // Collapse the parent
        parent.isShown = false

        // Search for something in a child entry
        let childName = parent.entries[0].name
        guard !childName.isEmpty else { return }

        rootModel.searchText = childName

        // Verify parent was expanded to show matching child
        #expect(parent.isShown == true, "Parent should be expanded when child matches search")
        #expect(parent.isHidden == false, "Parent should not be hidden when child matches")

        // Clear search - parent should collapse back to original state
        rootModel.searchText = ""

        #expect(parent.isShown == false, "Parent should collapse back to original state after search cleared")
        #expect(parent.isHidden == false, "Parent should not be hidden after search cleared")
    }

    @Test func searchPreservesOriginalStateAcrossMultipleSearches() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        try #require(root.rootManager != nil)

        let rootModel = SheetRootModel(linkControllable: root.rootManager!.itemRootController(for: .adventure)!.linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

        // Find an entry with children
        var parentEntry: SheetModel?
        for entry in rootModel.sheetModel.entries {
            if !entry.entries.isEmpty {
                parentEntry = entry
                break
            }
        }

        guard let parent = parentEntry, !parent.entries.isEmpty else {
            return
        }

        // Collapse the parent
        parent.isShown = false
        let originalState = parent.isShown

        // First search - should expand
        let childName = parent.entries[0].name
        guard !childName.isEmpty else { return }
        rootModel.searchText = childName
        #expect(parent.isShown == true, "First search should expand parent")

        // Modify search query - should still be expanded if child still matches
        rootModel.searchText = childName + "x"
        // Parent state depends on whether child still matches, but should restore from original first

        // Clear search - should return to original state
        rootModel.searchText = ""
        #expect(parent.isShown == originalState, "Should return to original collapsed state")

        // Second search - should expand again from original state
        rootModel.searchText = childName
        #expect(parent.isShown == true, "Second search should expand parent again")

        // Clear again - should return to original state
        rootModel.searchText = ""
        #expect(parent.isShown == originalState, "Should return to original state after second search")
    }
}
#endif
