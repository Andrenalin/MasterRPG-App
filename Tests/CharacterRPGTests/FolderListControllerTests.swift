// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

/// Tests for `SearchListController` driving CharacterRPG's list-mode and folder-mode search.
/// Each test constructs its own `SearchListController` backed by a shared, mutable
/// `ListDisplayModel` so the mode-switch test can observe results change on the same instance.
@MainActor
struct FolderListControllerTests {

    // MARK: - Helpers

    /// Returns a `SearchListController` + the `ListDisplayModel` that controls its mode.
    /// Sharing the model lets a single test flip `listMode` and re-call `results(text:)`.
    private func makeSUT(for root: CharacterRootModel,
                         listMode: ListDisplayModel.ListMode = .list,
                         displayMode: ListDisplayModel.DisplayMode = .medium)
        -> (sut: SearchListController, ldm: ListDisplayModel)
    {
        let ldm = ListDisplayModel(displayMode: displayMode, listMode: listMode)
        let sut = SearchListController(
            searchController: root.searchControllable,
            searchModel: SearchModel.preview(),
            listDisplayModel: ldm
        )
        return (sut, ldm)
    }

    /// Returns a `SearchLinkController` + its `ListDisplayModel` + the `SearchModel`.
    /// Setting `searchModel.filterId` activates the focused-character inspector path.
    private func makeLinkSUT(for root: CharacterRootModel,
                              listMode: ListDisplayModel.ListMode = .list,
                              focusId: UUID? = nil)
        -> (sut: SearchLinkController, ldm: ListDisplayModel, searchModel: SearchModel)
    {
        let ldm = ListDisplayModel(displayMode: .medium, listMode: listMode)
        let sm  = SearchModel.preview()
        sm.filterId = focusId
        let sut = SearchLinkController(
            searchController: root.searchControllable,
            searchModel: sm,
            listDisplayModel: ldm
        )
        return (sut, ldm, sm)
    }

    /// Creates a character with one group entry (has `valueId`) and adds named entries to the
    /// sub-value. Returns `(charId, groupEntryId, subValueId, subEntryId)`.
    private func makeCharacterWithGroupEntry(
        root: CharacterRootModel,
        characterName: String,
        groupEntryName: String,
        subEntryName: String
    ) async throws -> (charId: UUID, groupEntryId: UUID, subValueId: UUID, subEntryId: UUID) {
        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: characterName, itemId: charId)

        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: groupEntryId,
                                   name: groupEntryName, content: "")

        let char = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)

        let subEntryId = await root.editController.addNewGroup(itemId: subValueId)
        root.editController.update(itemId: subValueId, entryId: subEntryId,
                                   name: subEntryName, content: "")

        return (charId, groupEntryId, subValueId, subEntryId)
    }

    // MARK: - Empty search loads list

    @Test("Empty list search returns all visible root characters")
    func emptySearchLoadsAllVisibleCharacters() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let char1 = await root.itemController.addNew(type: .item)
        let char2 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Aragorn", itemId: char1)
        root.editController.reset(name: "Legolas",  itemId: char2)

        let (sut, _) = makeSUT(for: root)
        let results = await sut.results(text: "")

        let ids = results.map(\.itemId)
        #expect(ids.contains(char1), "Aragorn must appear on empty search")
        #expect(ids.contains(char2), "Legolas must appear on empty search")
    }

    @Test("Empty list search results are sorted alphabetically by name")
    func emptySearchSortsAlphabetically() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Charlie", itemId: idC)
        root.editController.reset(name: "Alice",   itemId: idA)
        root.editController.reset(name: "Bob",     itemId: idB)

        let (sut, _) = makeSUT(for: root)
        let names = await sut.results(text: "").map(\.itemName)
        let sorted = names.sorted { $0.localizedCompare($1) == .orderedAscending }
        #expect(names == sorted, "Empty-search results must be alphabetically sorted")
    }

    // MARK: - Search text filters list

    @Test("Non-empty list search returns only matching characters")
    func searchTextFiltersToMatchingCharacters() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let matchId   = await root.itemController.addNew(type: .item)
        let noMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Knight", itemId: matchId)
        root.editController.reset(name: "Forest Elf",    itemId: noMatchId)

        let (sut, _) = makeSUT(for: root)
        let results = await sut.results(text: "Dragon")

        let ids = results.map(\.itemId)
        #expect(ids.contains(matchId),    "Dragon Knight must match")
        #expect(!ids.contains(noMatchId), "Forest Elf must be filtered out")
    }

    @Test("Non-empty list search results are sorted by relevance (exact > contains)")
    func searchResultsSortedByRelevance() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let exactId    = await root.itemController.addNew(type: .item)
        let containsId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon",           itemId: exactId)
        root.editController.reset(name: "The Dragon Rider", itemId: containsId)

        let (sut, _) = makeSUT(for: root)
        let ids = await sut.results(text: "Dragon").map(\.itemId)

        let exactIdx    = try #require(ids.firstIndex(of: exactId))
        let containsIdx = try #require(ids.firstIndex(of: containsId))
        #expect(exactIdx < containsIdx, "Exact name match must rank above contains match")
    }

    // MARK: - Switching list mode updates results

    @Test("Switching to folder mode returns hierarchical results with folder nesting the character")
    func switchingToFolderModeReturnsHierarchicalResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let folderId = await root.itemController.addNew(type: .folder)
        let charId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Lair",   itemId: folderId)
        root.editController.reset(name: "Dragon Knight", itemId: charId)
        root.editController.addItem(itemId: charId, parentId: folderId)

        let (sut, ldm) = makeSUT(for: root, listMode: .list)

        // --- List mode: flat results, folder result carries no children ---
        let listResults = await sut.results(text: "Dragon")
        #expect(!listResults.isEmpty, "List mode must return results")
        if let folderFlat = listResults.first(where: { $0.itemId == folderId }) {
            #expect(folderFlat.children.isEmpty,
                    "List mode folder result must carry no hierarchical children")
        }

        // --- Switch to folder mode via the shared ListDisplayModel ---
        ldm.listMode = .folder
        let folderModeResults = await sut.results(text: "Dragon")

        let folderResult = try #require(
            folderModeResults.first(where: { $0.itemId == folderId }),
            "Dragon Lair must appear in folder mode results"
        )
        #expect(!folderResult.children.isEmpty,
                "Folder mode must nest Dragon Knight inside Dragon Lair's children")
        #expect(folderResult.children.map(\.itemId).contains(charId),
                "Dragon Knight must appear as a child of Dragon Lair in folder mode")
    }

    @Test("Folder mode groups characters under their parent folder")
    func folderModeGroupsCharactersUnderFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let folderId  = await root.itemController.addNew(type: .folder)
        let memberA   = await root.itemController.addNew(type: .item)
        let memberB   = await root.itemController.addNew(type: .item)
        let standalone = await root.itemController.addNew(type: .item)

        root.editController.reset(name: "Warriors",     itemId: folderId)
        root.editController.reset(name: "Swordsman",    itemId: memberA)
        root.editController.reset(name: "Archer",       itemId: memberB)
        root.editController.reset(name: "Lone Ranger",  itemId: standalone)

        root.editController.addItem(itemId: memberA, parentId: folderId)
        root.editController.addItem(itemId: memberB, parentId: folderId)

        let (sut, _) = makeSUT(for: root, listMode: .folder)
        let results = await sut.results(text: "")  // empty search — lazy load returns root nodes

        let rootIds = results.map(\.itemId)
        // Folder and standalone appear at root; members are inside the folder
        #expect(rootIds.contains(folderId),   "Warriors folder must be a root node")
        #expect(rootIds.contains(standalone), "Lone Ranger must be a root node")
        // Members should NOT appear as root nodes (they have parentId set)
        #expect(!rootIds.contains(memberA), "Swordsman must not appear as a root node")
        #expect(!rootIds.contains(memberB), "Archer must not appear as a root node")
    }

    // MARK: - SearchLinkController (inspector search)

    @Test("SearchLinkController: empty search without focus returns all visible characters sorted A→Z")
    func linkControllerEmptySearchNoFocusReturnsAllCharacters() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let idB = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Boromir", itemId: idB)
        root.editController.reset(name: "Aragorn", itemId: idA)

        let (sut, _, _) = makeLinkSUT(for: root)   // focusId == nil
        let results = await sut.results(text: "")
        let ids     = results.map(\.itemId)
        let names   = results.map(\.itemName)

        // Previously this path returned [] (first-appear blank list bug — now fixed).
        #expect(ids.contains(idA), "Aragorn must appear on empty inspector search")
        #expect(ids.contains(idB), "Boromir must appear on empty inspector search")
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Empty inspector search must return characters sorted A→Z")
    }

    @Test("SearchLinkController: search returns matching characters")
    func linkControllerSearchReturnsMatchingCharacters() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let matchId   = await root.itemController.addNew(type: .item)
        let noMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Knight", itemId: matchId)
        root.editController.reset(name: "Forest Elf",    itemId: noMatchId)

        let (sut, _, _) = makeLinkSUT(for: root)
        let results = await sut.results(text: "Dragon")

        let ids = results.map(\.itemId)
        #expect(ids.contains(matchId),    "Dragon Knight must appear")
        #expect(!ids.contains(noMatchId), "Forest Elf must be filtered out")
    }

    @Test("SearchLinkController common (no focus): entry match does NOT include the character — item-level only")
    func linkControllerCommonInspectorItemLevelOnly() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let charWithNameMatch  = await root.itemController.addNew(type: .item)
        let charWithEntryOnly  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Knight", itemId: charWithNameMatch)  // name matches
        root.editController.reset(name: "Eldrin",        itemId: charWithEntryOnly)  // name doesn't

        let entryId = await root.editController.addNewGroup(itemId: charWithEntryOnly)
        root.editController.update(itemId: charWithEntryOnly, entryId: entryId,
                                   name: "Dragon Resistance", content: "")

        let (sut, _, _) = makeLinkSUT(for: root)
        let results = await sut.results(text: "Dragon")

        // Character whose name matches must appear, with no entry children
        let nameResult = try #require(results.first(where: { $0.itemId == charWithNameMatch }),
                                      "Character with matching name must appear")
        #expect(nameResult.children.isEmpty,   "Common inspector: no entry children")
        #expect(nameResult.canOpen == false,   "Common inspector: canOpen must be false")

        // Character whose only match is an entry must NOT appear
        #expect(!results.contains(where: { $0.itemId == charWithEntryOnly }),
                "Character excluded: entries not searched in common inspector")
    }

    @Test("SearchLinkController: switching to folder mode returns hierarchical structure")
    func linkControllerFolderModeReturnsHierarchy() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let folderId = await root.itemController.addNew(type: .folder)
        let charId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Lair",   itemId: folderId)
        root.editController.reset(name: "Dragon Knight", itemId: charId)
        root.editController.addItem(itemId: charId, parentId: folderId)

        let (sut, ldm, _) = makeLinkSUT(for: root, listMode: .list)

        // List mode: folder and character appear flat (no nesting in SearchResult.children)
        let listResults = await sut.results(text: "Dragon")
        #expect(!listResults.isEmpty)
        if let folderFlat = listResults.first(where: { $0.itemId == folderId }) {
            #expect(folderFlat.children.isEmpty, "List mode folder must have no children")
        }

        // Switch to folder mode — same controller
        ldm.listMode = .folder
        let folderResults = await sut.results(text: "Dragon")
        let folderResult  = try #require(folderResults.first(where: { $0.itemId == folderId }))
        #expect(folderResult.children.map(\.itemId).contains(charId),
                "Folder mode must nest Dragon Knight inside Dragon Lair")
    }

    @Test("SearchLinkController: focused empty search returns character with all entries open")
    func linkControllerFocusedEmptySearchReturnsAllEntries() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let charId  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Thorin", itemId: charId)
        let entry1 = await root.editController.addNewGroup(itemId: charId)
        let entry2 = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entry1, name: "Strength",  content: "")
        root.editController.update(itemId: charId, entryId: entry2, name: "Dexterity", content: "")

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "")

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character must always be returned")
        #expect(charResult.children.count == 2, "All entries must be open as children")
        #expect(charResult.children.map(\.entryId).contains(entry1))
        #expect(charResult.children.map(\.entryId).contains(entry2))
    }

    @Test("SearchLinkController: focused search filters entries and still returns character")
    func linkControllerFocusedSearchFiltersEntries() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let charId     = await root.itemController.addNew(type: .item)
        let matchEntry = await root.editController.addNewGroup(itemId: charId)
        let noMatch    = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: matchEntry, name: "Dragon Breath", content: "")
        root.editController.update(itemId: charId, entryId: noMatch,    name: "Sword Skills",  content: "")

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "Dragon")

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character must always be returned")
        #expect(charResult.children.contains(where: { $0.entryId == matchEntry }),
                "Dragon Breath must appear as a child")
        #expect(!charResult.children.contains(where: { $0.entryId == noMatch }),
                "Sword Skills must not appear as a child")
    }

    // MARK: - Inspector children and open groups verification

    @Test("Inspector: group entry exposes its sub-value entries as open children")
    func inspectorGroupEntryHasSubEntriesAsOpenChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let (charId, groupEntryId, _, subEntryId) = try await makeCharacterWithGroupEntry(
            root: root,
            characterName: "Eldrin",
            groupEntryName: "Dragon Powers",
            subEntryName:   "Fire Breath"
        )

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "Dragon")

        let charResult  = try #require(results.first(where: { $0.itemId == charId }))
        let entryResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must be a child of the character result"
        )
        #expect(!entryResult.children.isEmpty,
                "Group entry must expose its sub-value entries as open children")
        #expect(entryResult.children.contains(where: { $0.entryId == subEntryId }),
                "Sub-entry must appear in the group entry's children")
    }

    @Test("Inspector: empty focused search opens all entries and all group sub-entries")
    func inspectorEmptyFocusedSearchOpensAllEntriesAndSubEntries() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let (charId, groupEntryId, _, subEntryId) = try await makeCharacterWithGroupEntry(
            root: root,
            characterName: "Thorin",
            groupEntryName: "Combat Skills",
            subEntryName:   "Axe Mastery"
        )

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "")         // empty search

        let charResult  = try #require(results.first(where: { $0.itemId == charId }),
                                       "Character must always be returned")
        let entryResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must be a child of character on empty search"
        )
        #expect(entryResult.children.contains(where: { $0.entryId == subEntryId }),
                "Sub-entries must be open (visible as entry's children) on empty search")
    }

    @Test("Inspector: sub-value name match opens the linking group entry with its sub-entries")
    func inspectorSubValueNameMatchOpensGroupEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let (charId, groupEntryId, subValueId, subEntryId) = try await makeCharacterWithGroupEntry(
            root: root,
            characterName: "Legolas",
            groupEntryName: "Special Ability",
            subEntryName:   "Arrow Rain"
        )
        // Name the sub-value item itself so it matches the search
        root.editController.reset(name: "Dragon Sight", itemId: subValueId)

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "Dragon")

        let charResult  = try #require(results.first(where: { $0.itemId == charId }))
        let entryResult = try #require(
            charResult.children.first(where: { $0.entryId == groupEntryId }),
            "Group entry must be included because its sub-value name matches"
        )
        #expect(!entryResult.children.isEmpty,
                "Matched group entry must expose its sub-entries as open children")
        #expect(entryResult.children.contains(where: { $0.entryId == subEntryId }))
    }

    @Test("Inspector: no search match returns character with no open children")
    func inspectorNoMatchReturnsCharacterWithNoChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let charId  = await root.itemController.addNew(type: .item)
        let entryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.reset(name: "Knight",   itemId: charId)
        root.editController.update(itemId: charId, entryId: entryId,
                                   name: "Sword Skill", content: "Very skilled")

        let (sut, _, _) = makeLinkSUT(for: root, focusId: charId)
        let results = await sut.results(text: "Dragon")

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character must always be returned")
        #expect(charResult.children.isEmpty,
                "No entries match Dragon — children must be empty (no open children)")
    }
}
