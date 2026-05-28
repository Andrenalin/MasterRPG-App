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

        let results = await sut.searchItems(searchText: "")
        #expect(results.isEmpty)
    }

    @Test func visibleCharacterMatchingNameAppearsInResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Aldric the Bold", itemId: itemId)

        let results = await sut.searchItems(searchText: "Aldric")
        #expect(results.contains { $0.itemId == itemId })
    }

    @Test func hiddenCharacterIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Hidden Knight", itemId: itemId)
        root.editController.reset(displayState: 1, itemId: itemId)

        let results = await sut.searchItems(searchText: "Hidden")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func deletedCharacterIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Deleted Ranger", itemId: itemId)
        root.editController.reset(displayState: 2, itemId: itemId)

        let results = await sut.searchItems(searchText: "Deleted")
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
        let results = await sut.searchItems(searchText: "SubValueStrength")
        #expect(results.contains { $0.itemId == childId } == false)
    }

    @Test func nonMatchingVisibleCharacterIsExcluded() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Goblin Scout", itemId: itemId)

        let results = await sut.searchItems(searchText: "Dragon")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func descriptionMatchReturnsCharacter() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Village Elder", itemId: itemId)
        root.editController.reset(description: "Keeper of ancient lore", itemId: itemId)

        let results = await sut.searchItems(searchText: "ancient lore")
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

        let results = await sut.searchItems(searchText: "Rogue")
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

        let results = await sut.searchItems(searchText: "forest")
        let matchIds = results.map(\.itemId)

        let nameIndex = try #require(matchIds.firstIndex(of: nameMatchId))
        let descIndex = try #require(matchIds.firstIndex(of: descMatchId))

        #expect(nameIndex < descIndex)
    }
}
