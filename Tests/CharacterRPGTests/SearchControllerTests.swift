// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct SearchControllerTests {

    // MARK: - searchItems

    @Test func emptySearchTextReturnsNoResults() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.searchController

        let results = await sut.globalSearchResults(searchText: "")
        #expect(results.isEmpty)
    }

    @Test func visibleCharacterMatchingNameAppearsInResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Aldric the Bold", itemId: itemId)

        let results = await sut.globalSearchResults(searchText: "Aldric")
        #expect(results.contains { $0.itemId == itemId })
    }

    @Test func hiddenCharacterIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Hidden Knight", itemId: itemId)
        root.editController.reset(displayState: 1, itemId: itemId)

        let results = await sut.globalSearchResults(searchText: "Hidden")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func deletedCharacterIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Deleted Ranger", itemId: itemId)
        root.editController.reset(displayState: 2, itemId: itemId)

        let results = await sut.globalSearchResults(searchText: "Deleted")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func groupItemIsExcludedEvenWhenVisibleAndNameMatches() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        // Create parent and attach a group sub-value to it
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await root.editController.addNewGroup(itemId: parentId)

        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Make the group item fully visible (displayState 0) and give it a searchable name
        root.editController.reset(displayState: 0, itemId: childId)
        root.editController.reset(name: "SubValueStrength", itemId: childId)

        // groupId != nil must exclude it from list search even when displayState == 0
        let results = await sut.globalSearchResults(searchText: "SubValueStrength")
        #expect(results.contains { $0.itemId == childId } == false)
    }

    @Test func nonMatchingVisibleCharacterIsExcluded() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Goblin Scout", itemId: itemId)

        let results = await sut.globalSearchResults(searchText: "Dragon")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func descriptionMatchReturnsCharacter() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Village Elder", itemId: itemId)
        root.editController.reset(description: "Keeper of ancient lore", itemId: itemId)

        let results = await sut.globalSearchResults(searchText: "ancient lore")
        #expect(results.contains { $0.itemId == itemId })
    }

    // MARK: - relevance ordering

    @Test func resultsAreSortedByRelevanceDescending() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        // Exact name match → score 115
        let exactId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rogue", itemId: exactId)

        // Prefix name match → score 65
        let prefixId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rogueborn", itemId: prefixId)

        // Name contains match → score 40
        let containsId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "The Rogue Assassin", itemId: containsId)

        let results = await sut.globalSearchResults(searchText: "Rogue")
        let matchIds = results.map(\.itemId)

        let exactIndex = try #require(matchIds.firstIndex(of: exactId))
        let prefixIndex = try #require(matchIds.firstIndex(of: prefixId))
        let containsIndex = try #require(matchIds.firstIndex(of: containsId))

        #expect(exactIndex < prefixIndex)
        #expect(prefixIndex < containsIndex)
    }

    @Test func descriptionMatchHasLowerRelevanceThanNameMatch() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        // Name contains → score 40
        let nameMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Forest Tracker", itemId: nameMatchId)

        // Description only → score 25
        let descMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Wandering Merchant", itemId: descMatchId)
        root.editController.reset(description: "Expert forest tracker and guide", itemId: descMatchId)

        let results = await sut.globalSearchResults(searchText: "forest")
        let matchIds = results.map(\.itemId)

        let nameIndex = try #require(matchIds.firstIndex(of: nameMatchId))
        let descIndex = try #require(matchIds.firstIndex(of: descMatchId))

        #expect(nameIndex < descIndex)
    }

    // MARK: - Inspector search, focusId == nil (CoreRPG-compatible: entries as children)

    @Test("Inspector nil focus: character appears only when ITS OWN NAME matches — entries are not searched")
    func inspectorNilFocusOnlyNameMatch() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charWithNameMatch  = await root.itemController.addNew(type: .item)
        let charWithEntryOnly  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Knight", itemId: charWithNameMatch)  // name matches
        root.editController.reset(name: "Eldrin",        itemId: charWithEntryOnly)  // name doesn't match

        // Only entry of Eldrin matches — but common inspector never searches entries
        let entryId = await root.editController.addNewGroup(itemId: charWithEntryOnly)
        root.editController.update(itemId: charWithEntryOnly, entryId: entryId,
                                   name: "Dragon Strength", content: "Very high")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        // Common inspector: item-level match only, no entry children, no canOpen
        let nameMatchResult = try #require(results.first(where: { $0.itemId == charWithNameMatch }),
                                           "Character whose NAME matches 'Dragon' must appear")
        #expect(nameMatchResult.children.isEmpty, "Common inspector: no entry children")
        #expect(nameMatchResult.canOpen == false,  "Common inspector: canOpen must be false")

        #expect(!results.contains(where: { $0.itemId == charWithEntryOnly }),
                "Character whose only match is an entry must be excluded — entries not searched in common inspector")
    }

    @Test("Inspector nil focus: character excluded when neither name nor description match")
    func inspectorNilFocusNoMatchExcludes() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Knight", itemId: charId)
        let entryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entryId, name: "Sword skill", content: "Very skilled")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        #expect(!results.contains(where: { $0.itemId == charId }),
                "Character with no matching name or description must be excluded (entries not searched in common inspector)")
    }

    // MARK: - Inspector search, focusId = character (focused character inspector)

    @Test("Focused inspector: empty search returns character with all entries")
    func focusedInspectorEmptySearchReturnsCharacterWithAllEntries() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Thorin", itemId: charId)
        let entry1 = await root.editController.addNewGroup(itemId: charId)
        let entry2 = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entry1, name: "Strength", content: "")
        root.editController.update(itemId: charId, entryId: entry2, name: "Dexterity", content: "")

        let results = await sut.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character must always be returned")
        #expect(charResult.children.count == 2, "All entries must appear as children on empty search")
        // shouldOpen must be true so appendToFlat expands the row immediately — no chevron tap needed
        #expect(charResult.shouldOpen == true,
                "shouldOpen must be set so entries are visible on first appear without user interaction")
    }

    @Test("Focused inspector: empty search — group entry children appear as entry's children")
    func focusedInspectorEmptySearchGroupEntryHasSubEntriesAsChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Thorin", itemId: charId)
        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        // The group entry has a valueId → a sub-value item
        let char = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)
        // Add an entry to the sub-value
        let subEntry1 = await root.editController.addNewGroup(itemId: subValueId)
        root.editController.update(itemId: subValueId, entryId: subEntry1, name: "SubStrength", content: "")

        let results = await sut.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        let entryResult = try #require(charResult.children.first(where: { $0.entryId == groupEntryId }),
                                       "Group entry must appear as child of character")
        #expect(!entryResult.children.isEmpty,
                "Sub-value entries must appear as children of the group entry")
        #expect(entryResult.children.contains(where: { $0.entryId == subEntry1 }),
                "Sub-entry must be in entry's children")
    }

    @Test("Focused inspector: entry name match — only matching entry returned")
    func focusedInspectorEntryNameMatch() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Eldrin — no dragon here", itemId: charId)
        let matchEntry = await root.editController.addNewGroup(itemId: charId)
        let noMatchEntry = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: matchEntry, name: "Dragon Breath", content: "")
        root.editController.update(itemId: charId, entryId: noMatchEntry, name: "Sword Skills", content: "")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Character must always be returned regardless of its own name")
        #expect(charResult.children.contains(where: { $0.entryId == matchEntry }),
                "Entry whose name matches must appear")
        #expect(!charResult.children.contains(where: { $0.entryId == noMatchEntry }),
                "Entry with no match must be excluded")
    }

    @Test("Focused inspector: entry content match")
    func focusedInspectorEntryContentMatch() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        let entryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entryId, name: "Fire Resistance", content: "Immune to dragon fire")

        let results = await sut.inspectorSearchResults(
            searchText: "dragon",
            listMode: .list,
            displayMode: .compact,   // displayMode has no effect in focused inspector
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        #expect(charResult.children.contains(where: { $0.entryId == entryId }),
                "Entry whose content matches must appear even in compact display mode")
    }

    @Test("Focused inspector: sub-value item name match includes its group entry")
    func focusedInspectorSubValueNameMatch() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        // The group entry points to a sub-value item — name it "Dragon Ability"
        let char = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)
        root.editController.reset(name: "Dragon Ability", itemId: subValueId)

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        #expect(charResult.children.contains(where: { $0.entryId == groupEntryId }),
                "Group entry whose sub-value name matches must be included")
    }

    @Test("Focused inspector: no match excludes all entries but still returns character")
    func focusedInspectorNoMatchReturnsEmptyChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Knight", itemId: charId)
        let entryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entryId, name: "Sword", content: "Sharp blade")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Focused character must always be returned")
        #expect(charResult.children.isEmpty, "No entries match Dragon — children must be empty")
    }

    @Test("Focused inspector: matching entry with sub-value gets sub-value entries as its children")
    func focusedInspectorMatchingEntryHasSubValueEntriesAsChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        let groupEntryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: groupEntryId, name: "Dragon Powers", content: "")

        // The group entry points to a sub-value; add entries to that sub-value
        let char = root.itemController.itemOrEmpty(for: charId)
        let groupEntry = try #require(char.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)
        let subEntry = await root.editController.addNewGroup(itemId: subValueId)
        root.editController.update(itemId: subValueId, entryId: subEntry, name: "Fire breath", content: "")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: charId
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }))
        let entryResult = try #require(charResult.children.first(where: { $0.entryId == groupEntryId }),
                                       "Matching group entry must be a child")
        #expect(!entryResult.children.isEmpty,
                "Matching entry's sub-value entries must appear as the entry's children")
        #expect(entryResult.children.contains(where: { $0.entryId == subEntry }))
    }
}

// MARK: - listSearchResults: list mode (CharacterRPG-specific behaviours)

/// CharacterRPG list mode search behavior:
///  1. `groupId != nil` items (sub-values) are always excluded.
///  2. `specialCategory` items (groups/folders) are EXCLUDED (flat list shows only regular characters).
///  3. Empty search: alphabetical order (A→Z).
///  4. Non-empty search: relevance order with alphabetical tiebreaker via `sortedByRelevance()`.
@MainActor
struct ListSearchResultsTests {

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    // MARK: groupId filter

    @Test("List mode excludes sub-value items (groupId != nil)")
    func listModeExcludesSubValueItems() async throws {
        let root = try await makeRoot()

        let parentId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Warrior", itemId: parentId)

        let groupEntryId = await root.editController.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)
        root.editController.reset(name: "Warrior Strength", itemId: subValueId)  // searchable name

        let results = await root.searchController.listSearchResults(
            searchText: "Warrior",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(ids.contains(parentId),    "Parent character must appear")
        #expect(!ids.contains(subValueId), "Sub-value (groupId != nil) must be excluded from list mode")
    }

    @Test("List mode excludes specialCategory items (folders) — they only appear in folder mode")
    func listModeExcludesSpecialCategoryItems() async throws {
        let root = try await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Dragon Group", itemId: folderId)
        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Regular Dragon", itemId: charId)

        let results = await root.searchController.listSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(!ids.contains(folderId), "specialCategory folder must be excluded from list mode")
        #expect(ids.contains(charId),    "Regular character must appear in list mode")
    }
    
    @Test("List mode empty search excludes folders — returns only characters sorted A→Z")
    func listModeEmptySearchExcludesFolders() async throws {
        let root = try await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let charC = await root.itemController.addNew(type: .item)
        let charA = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Heroes Folder", itemId: folderId)
        root.editController.reset(name: "Cassia",        itemId: charC)
        root.editController.reset(name: "Aldric",        itemId: charA)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)
        let names = results.map(\.itemName)

        #expect(!ids.contains(folderId), "Folder must be excluded from empty list search")
        #expect(ids.contains(charC) && ids.contains(charA), "Characters must appear")
        #expect(names == ["Aldric", "Cassia"], "Characters must be sorted A→Z")
    }
    
    @Test("List mode non-empty search excludes folders even when folder name matches")
    func listModeNonEmptySearchExcludesFoldersEvenWhenNameMatches() async throws {
        let root = try await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon Vault", itemId: folderId)
        root.editController.reset(name: "Dragon Slayer", itemId: charId)

        let results = await root.searchController.listSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(!ids.contains(folderId), "Folder must not appear in list mode even when name matches search")
        #expect(ids.contains(charId),    "Character with matching name must appear")
    }

    @Test("List mode empty search returns all root characters sorted A→Z, no sub-values")
    func listModeEmptySearchSortsAlphabetically() async throws {
        let root = try await makeRoot()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        let idB = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Cassia", itemId: idC)
        root.editController.reset(name: "Aldric", itemId: idA)
        root.editController.reset(name: "Berin",  itemId: idB)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let names = results.map(\.itemName)
        let sorted = names.sorted { $0.localizedCompare($1) == .orderedAscending }

        #expect(names == sorted, "Empty search must return characters sorted A→Z")
    }

    @Test("List mode non-empty search uses relevance order with alphabetical tiebreaker")
    func listModeNonEmptySearchSortsByRelevance() async throws {
        let root = try await makeRoot()

        let exactId    = await root.itemController.addNew(type: .item)
        let containsId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rogue",             itemId: exactId)
        root.editController.reset(name: "Rogue Shadowstep",  itemId: containsId)

        let results = await root.searchController.listSearchResults(
            searchText: "Rogue",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)
        let eIdx = try #require(ids.firstIndex(of: exactId))
        let cIdx = try #require(ids.firstIndex(of: containsId))

        #expect(eIdx < cIdx, "Exact name match must rank above contains match")
    }

    // MARK: folder mode

    @Test("Folder mode excludes sub-value items (groupId != nil) from the tree")
    func folderModeExcludesSubValueItems() async throws {
        let root = try await makeRoot()

        let parentId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Ranger", itemId: parentId)

        let groupEntryId = await root.editController.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == groupEntryId }))
        let subValueId = try #require(groupEntry.valueId)
        root.editController.reset(name: "Ranger Dexterity", itemId: subValueId)

        let results = await root.searchController.listSearchResults(
            searchText: "Ranger",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )
        let allIds = results.flatMap { [$0.itemId] + $0.children.map(\.itemId) }

        #expect(allIds.contains(parentId),    "Parent character must appear")
        #expect(!allIds.contains(subValueId), "Sub-value (groupId != nil) must not appear in folder tree")
    }

    @Test("Folder mode empty search: all root characters, sorted A→Z, canOpen for folders")
    func folderModeEmptySearchShowsRootCharacters() async throws {
        let root = try await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let charId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Zultan",   itemId: folderId)
        root.editController.reset(name: "Aerindel", itemId: charId)

        let results = await root.searchController.listSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )
        let ids   = results.map(\.itemId)
        let names = results.map(\.itemName)

        #expect(ids.contains(folderId), "Folder must appear in empty folder search")
        #expect(ids.contains(charId),   "Character must appear in empty folder search")
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Empty folder search must sort root items A→Z")
        let folderResult = try #require(results.first(where: { $0.itemId == folderId }))
        #expect(folderResult.canOpen == true, "Folder must have canOpen=true on empty search (lazy load)")
    }
}

// MARK: - Inspector: empty search and folder mode fixes

@MainActor
struct InspectorSearchFixTests {

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    @Test("Inspector non-focused empty search returns all visible characters (not empty)")
    func inspectorEmptySearchReturnsAllCharacters() async throws {
        let root = try await makeRoot()

        let char1 = await root.itemController.addNew(type: .item)
        let char2 = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Aldric", itemId: char1)
        root.editController.reset(name: "Berin",  itemId: char2)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(ids.contains(char1), "Aldric must appear on empty inspector search")
        #expect(ids.contains(char2), "Berin must appear on empty inspector search")
    }

    @Test("Inspector non-focused empty search returns characters sorted A→Z")
    func inspectorEmptySearchSortsAlphabetically() async throws {
        let root = try await makeRoot()

        let idC = await root.itemController.addNew(type: .item)
        let idA = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Cedric", itemId: idC)
        root.editController.reset(name: "Asha",   itemId: idA)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let names = results.map(\.itemName)

        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending },
                "Empty inspector search must return characters sorted A→Z")
    }

    @Test("Inspector common (no focus): characters always have canOpen=false — no entry expansion in common view")
    func inspectorCommonNeverHasCanOpen() async throws {
        let root = try await makeRoot()

        let charWithEntries    = await root.itemController.addNew(type: .item)
        let charWithoutEntries = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "With Entries",    itemId: charWithEntries)
        root.editController.reset(name: "Without Entries", itemId: charWithoutEntries)
        _ = await root.editController.addNewGroup(itemId: charWithEntries)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let withResult    = try #require(results.first(where: { $0.itemId == charWithEntries }))
        let withoutResult = try #require(results.first(where: { $0.itemId == charWithoutEntries }))

        // Common inspector: characters are link targets, not character sheets.
        // canOpen must be false regardless of whether they have entries.
        #expect(withResult.canOpen    == false, "Common inspector: canOpen must be false even with entries")
        #expect(withoutResult.canOpen == false, "Common inspector: canOpen must be false")
        #expect(withResult.children.isEmpty,    "Common inspector: no entry children in results")
    }

    @Test("Inspector sub-value (groupId != nil) excluded from empty search results")
    func inspectorEmptySearchExcludesSubValues() async throws {
        let root = try await makeRoot()

        let parentId     = await root.itemController.addNew(type: .item)
        let groupEntryId = await root.editController.addNewGroup(itemId: parentId)
        let parent       = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry   = try #require(parent.entries.first(where: { $0.id == groupEntryId }))
        let subValueId   = try #require(groupEntry.valueId)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(!ids.contains(subValueId), "Sub-value (groupId != nil) must not appear in inspector empty results")
    }

    @Test("Inspector folder mode: empty search returns all characters without space-trick filtering")
    func inspectorFolderModeEmptySearchShowsAllCharacters() async throws {
        let root = try await makeRoot()

        // Items with single-word names have no space — the old " " trick filtered them out
        let singleWord = await root.itemController.addNew(type: .item)
        let multiWord  = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Rogue",         itemId: singleWord)
        root.editController.reset(name: "Forest Ranger", itemId: multiWord)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )
        let ids = results.map(\.itemId)

        #expect(ids.contains(singleWord), "Single-word name 'Rogue' must appear (no \" \" trick)")
        #expect(ids.contains(multiWord),  "Multi-word name 'Forest Ranger' must appear")
    }

    @Test("Inspector folder mode: canOpen=true for all folders on empty search (lazy load)")
    func inspectorFolderModeEmptySearchFolderHasCanOpenTrue() async throws {
        let root = try await makeRoot()

        let folderId = await root.itemController.addNew(type: .folder)
        let charId   = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Heroes Guild", itemId: folderId)
        root.editController.addItem(itemId: charId, parentId: folderId)

        let results = await root.searchController.inspectorSearchResults(
            searchText: "",
            listMode: .folder,
            displayMode: .medium,
            focusId: nil
        )
        let folderResult = try #require(results.first(where: { $0.itemId == folderId }))

        #expect(folderResult.canOpen == true,
                "Folder must have canOpen=true on empty search so FolderListControllable can lazy-load")
        #expect(folderResult.children.isEmpty,
                "Folder children must not be pre-fetched on empty search")
    }
}
