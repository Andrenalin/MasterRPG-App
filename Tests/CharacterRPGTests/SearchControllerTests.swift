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

    @Test("Inspector nil focus: entry name match gives entry as child of character result")
    func inspectorNilFocusEntryMatchGivesEntryAsChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let charId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Eldrin", itemId: charId)
        let entryId = await root.editController.addNewGroup(itemId: charId)
        root.editController.update(itemId: charId, entryId: entryId, name: "Dragon Strength", content: "Very high")

        let results = await sut.inspectorSearchResults(
            searchText: "Dragon",
            listMode: .list,
            displayMode: .medium,
            focusId: nil
        )

        let charResult = try #require(results.first(where: { $0.itemId == charId }),
                                      "Character must appear because its entry name matches")
        #expect(!charResult.children.isEmpty, "Matching entry must be a child of the character result")
        #expect(charResult.children.contains(where: { $0.entryId == entryId }),
                "The matching entry must appear in children")
    }

    @Test("Inspector nil focus: no match excludes character")
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
                "Character with no matching name, description, or entries must be excluded")
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
