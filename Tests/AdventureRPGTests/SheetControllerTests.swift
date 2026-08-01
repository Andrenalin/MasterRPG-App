// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import CharacterRPG

@MainActor
struct SheetControllerTests {
    func linkRegisterController(for root: AdventureRootModel) -> LinkRegisterController {
        LinkRegisterController(root: RootManager.init(anyRoot: root))
    }

    func rootManager(for root: AdventureRootModel) throws -> RootManager {
        try #require(root.rootManager)
    }

    func adventureRootController(for root: AdventureRootModel) throws -> ItemRootController {
        let rootManager = try rootManager(for: root)
        return try #require(rootManager.itemRootController(for: .adventure))
    }

    @Test func adventureSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let model = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let model = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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

        let model = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

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

        let entries = sut.sheetEntries(root: try rootManager(for: root), itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false) // Links default to hidden
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func duplicateOrcLinksRemainDistinctInEditorAndSheet() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        let rootManager = try rootManager(for: root)
        let orc = ValueModel(
            id: UUID(),
            name: "Orc",
            description: "A fierce orc",
            category: .character
        )
        root.characterRoot.editController.save(updated: orc, message: "Add Orc")

        let entry = AdventureEntryModel.fixture(name: "Encounter", content: "")
        let adventure = AdventureModel(
            id: UUID(),
            name: "Orc Encounter",
            entries: [entry]
        )
        root.editController.save(updated: adventure, message: "Add Adventure")

        // When
        for _ in 0..<2 {
            root.editController.add(
                link: "Orc",
                module: .value,
                itemId: orc.id,
                entryId: nil,
                destinationItemId: adventure.id,
                destinationEntryId: entry.id
            )
        }

        // Then
        let updatedEntry = root.itemController.itemOrEmpty(for: adventure.id)[entry.id]
        let parsedLinks = LinkReplaceController.links(for: updatedEntry.content)
        #expect(parsedLinks.count == 2)
        #expect(parsedLinks.map(\.name) == ["Orc", "Orc"])
        #expect(parsedLinks.map(\.itemId) == [orc.id, orc.id])
        #expect(parsedLinks.map(\.linkNumber) == [0, 1])

        let source = ItemRowModel(
            itemId: adventure.id,
            entryId: entry.id,
            typeId: .adventure
        )
        let registeredLinks = root.linkRegisterController.linksFrom(source: source)
            .filter(\.isSheetLink)
        #expect(registeredLinks.count == 2)
        #expect(Set(registeredLinks.map(\.id)).count == 2)
        #expect(registeredLinks.map(\.linkNumber) == [0, 1])

        let textEditModel = TextEditModel(
            linkRegisterController: root.linkRegisterController
        )
        textEditModel.reset(entry: updatedEntry, source: source)
        #expect(textEditModel.links.count == 2)
        #expect(Set(textEditModel.links.map(\.id)).count == 2)
        #expect(String(textEditModel.attributedText.characters) == "Orc Orc")
        textEditModel.resetText()
        #expect(textEditModel.text == updatedEntry.content)

        let sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: try adventureRootController(for: root).linkControllable,
            sheetControllable: SheetController(itemController: root.itemController),
            itemId: adventure.id,
            isEditor: false
        )
        let entrySheet = try #require(
            sheetRootModel.sheetModel.entries.first {
                $0.source.entryId == entry.id
            }
        )
        let orcSheets = entrySheet.entries.filter {
            $0.source.itemId == orc.id && $0.source.typeId == .value
        }
        #expect(orcSheets.count == 2)
        #expect(Set(orcSheets.map(\.id)).count == 2)
        #expect(orcSheets.map(\.linkNumber) == [0, 1])
        #expect(orcSheets.allSatisfy { !$0.isShown })

        sheetRootModel.toggle(
            id: .entryContent(entry.id),
            itemId: orc.id,
            module: .value,
            linkNumber: 0
        )
        #expect(orcSheets[0].isShown)
        #expect(!orcSheets[1].isShown)

        sheetRootModel.toggle(
            id: .entryContent(entry.id),
            itemId: orc.id,
            module: .value,
            linkNumber: 1
        )
        #expect(orcSheets[0].isShown)
        #expect(orcSheets[1].isShown)

        sheetRootModel.toggle(
            id: .entryContent(entry.id),
            itemId: orc.id,
            module: .value,
            linkNumber: 0
        )
        #expect(!orcSheets[0].isShown)
        #expect(orcSheets[1].isShown)
    }

    @Test func adventureSheetLinkToAdventureModule() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let entries = sut.sheetEntries(root: try rootManager(for: root), itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

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

        let modelShown = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func adventureSheetOnlyMaterializesRootLevel() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let modelFolded = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func linkedAdventureMaterializesWhenUnfolded() async throws {
        let root = try await MockRoot.importTestData()
        let rootManager = try rootManager(for: root)
        let childEntry = AdventureEntryModel.fixture(name: "Child scene", content: "Child content")
        let child = AdventureModel(
            id: UUID(),
            name: "Child Adventure",
            entries: [childEntry]
        )
        let parentEntry = AdventureEntryModel.fixture(
            name: "Child Adventure",
            content: "Open the child adventure",
            adventureId: child.id
        )
        let parent = AdventureModel(
            id: UUID(),
            name: "Parent Adventure",
            entries: [parentEntry]
        )
        root.itemController.replace(model: child, isInsert: true)
        root.itemController.replace(model: parent, isInsert: true)

        let sut = SheetController(itemController: root.itemController)
        let parentSheet = sut.sheet(
            root: rootManager,
            itemId: parent.id,
            destination: nil,
            level: 0,
            isShown: true,
            moduleDepth: 0,
            isEditor: false
        )
        let groupSheet = try #require(parentSheet.entries.first)
        let linkedSheet = try #require(groupSheet.entries.first)

        #expect(linkedSheet.source.itemId == child.id)
        #expect(linkedSheet.isFolded)
        #expect(linkedSheet.entries.isEmpty)

        sut.unfold(root: rootManager, sheetModel: linkedSheet)

        #expect(!linkedSheet.isFolded)
        #expect(linkedSheet.entries.map(\.source.entryId) == [childEntry.id])
    }

    @Test func adventureSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.adventure)
        let model = sut.sheet(root: try rootManager(for: root), itemId: itemId!, destination: destination, level: 0, isShown: true, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
    }

    @Test func searchPreservesIsShownState() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

        // Create model - searchText is "" by default
        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

        let rootModel = SheetRootModel(rootManager: try rootManager(for: root), linkControllable: try adventureRootController(for: root).linkControllable, sheetControllable: sut, itemId: itemId!, isEditor: false)

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

    @Test func adventureUpdateRefreshesChangedFieldsAndEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()
        let originalPhotoId = UUID()
        let updatedPhotoId = UUID()
        let keptEntry = AdventureEntryModel.fixture(name: "Old Beat", content: "Old text")
        let removedEntry = AdventureEntryModel.fixture(name: "Removed Beat", content: "Gone")

        root.itemController.replace(
            model: AdventureModel(
                id: itemId,
                name: "Old Adventure",
                description: "Old description",
                photoId: originalPhotoId,
                entries: [keptEntry, removedEntry]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: try rootManager(for: root), itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        var updatedEntry = keptEntry
        updatedEntry.name = "Updated Beat"
        updatedEntry.content = "Updated text"
        let newEntry = AdventureEntryModel.fixture(name: "New Beat", content: "Fresh text")
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.name = "Updated Adventure"
        item.description = "Updated description"
        item.photoId = updatedPhotoId
        item.entries = [updatedEntry, newEntry]

        sut.update(root: try rootManager(for: root), sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Updated Adventure")
        #expect(sheetModel.description == "Updated description")
        #expect(sheetModel.inlineEntries.map(\.source.itemId) == [updatedPhotoId])
        #expect(sheetModel.entries.map(\.source.entryId).contains(keptEntry.id))
        #expect(!sheetModel.entries.map(\.source.entryId).contains(removedEntry.id))
        #expect(sheetModel.entries.map(\.source.entryId).contains(newEntry.id))
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.name == "Updated Beat")
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.description == "Updated text")
    }

    @Test func adventureUpdateRefreshesEntryConvertedToGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()
        let entry = AdventureEntryModel.fixture(name: "Rumors", content: "A collection of rumors.")

        root.itemController.replace(
            model: AdventureModel(id: itemId, name: "Adventure", description: "", entries: [entry]),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: try rootManager(for: root), itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)
        let entrySheet = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(entrySheet.sheetType == .item)

        let groupId = await root.editController.convertToGroup(itemId: itemId, entryId: entry.id, existingItemId: nil)

        sut.update(root: try rootManager(for: root), sheetModel: sheetModel, isEditor: false)

        let updatedEntrySheet = try #require(sheetModel.entries.first(where: { $0.source.entryId == entry.id }))
        #expect(updatedEntrySheet.sheetType == .group, "Converting an entry to a group must refresh its sheetType")
        #expect(updatedEntrySheet.entries.contains(where: { $0.source.itemId == groupId }), "Converting an entry to a group must surface the new group's nested sheet")
    }

    @Test func convertToGroupResetsCachedLinkHighlightTextModel() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = UUID()
        let entry = AdventureEntryModel.fixture(name: "Rumors", content: "A collection of rumors.")

        root.itemController.replace(
            model: AdventureModel(id: itemId, name: "Adventure", description: "", entries: [entry]),
            isInsert: true
        )

        let sheetController = SheetController(itemController: root.itemController)
        let sheetRootModel = SheetRootModel(
            rootManager: try rootManager(for: root),
            linkControllable: try adventureRootController(for: root).linkControllable,
            sheetControllable: sheetController,
            itemId: itemId,
            isEditor: false
        )

        // Simulate the row already having been rendered (and its name text cached) before conversion.
        let nameModel = sheetRootModel.linkTextModel(for: .entry(entry.id), text: "Rumors")
        #expect(nameModel.text == "Rumors")

        let groupId = await sheetRootModel.convertEntryToGroup(
            source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: .adventure),
            existingItemId: nil
        )
        #expect(groupId != nil)

        // The cached model must pick up the new link text on its own, without requiring the
        // owning view to be torn down and rebuilt.
        #expect(nameModel.text != "Rumors", "Cached LinkHighlightTextModel must be reset after converting an entry to a group")
        #expect(nameModel.text.contains("\(URL.appScheme)://"), "Cached LinkHighlightTextModel must reflect the entry's new link text")
    }

    @Test func adventureUpdateLeavesFoldedEntriesCollapsed() async throws {
        let root = try await MockRoot.importTestData()
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()

        root.itemController.replace(
            model: AdventureModel(
                id: itemId,
                name: "Folded Adventure",
                description: "Folded description",
                entries: [AdventureEntryModel.fixture(name: "Hidden", content: "Hidden text")]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: try rootManager(for: root), itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 4, isEditor: false)
        root.itemController.itemOrEmpty(for: itemId).name = "Folded Updated"

        sut.update(root: try rootManager(for: root), sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Folded Updated")
        #expect(sheetModel.isFolded)
        #expect(sheetModel.entries.isEmpty)
    }
}
#endif
