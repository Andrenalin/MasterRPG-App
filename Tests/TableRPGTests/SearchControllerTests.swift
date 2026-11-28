// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct SearchControllerTests {

    // MARK: - searchItems

    @Test func emptySearchTextReturnsNoResults() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.searchController

        let results = await sut.globalSearchResults(searchText: "")
        #expect(results.isEmpty)
    }

    @Test func visibleItemMatchingNameAppearsInResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Goblin Warrior", itemId: itemId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "Goblin")
        #expect(results.contains { $0.itemId == itemId })
    }

    @Test func hiddenItemIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Hidden Creature", itemId: itemId, forceSave: false)
        root.editController.reset(displayState: 1, itemId: itemId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "Hidden")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func deletedItemIsExcludedFromResults() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Deleted Creature", itemId: itemId, forceSave: false)
        root.editController.reset(displayState: 2, itemId: itemId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "Deleted")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func nonMatchingVisibleItemIsExcluded() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Goblin", itemId: itemId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "Dragon")
        #expect(results.contains { $0.itemId == itemId } == false)
    }

    @Test func descriptionMatchReturnsItem() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Loot Table", itemId: itemId, forceSave: false)
        root.editController.reset(description: "Found in dark dungeons", itemId: itemId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "dungeons")
        #expect(results.contains { $0.itemId == itemId })
    }

    // MARK: - relevance ordering

    @Test func resultsAreSortedByRelevanceDescending() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.searchController

        // Exact name match → score 115
        let exactId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragon", itemId: exactId, forceSave: false)

        // Prefix name match → score 65
        let prefixId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dragonborn", itemId: prefixId, forceSave: false)

        // Name contains match → score 40
        let containsId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "The Dragon Rider", itemId: containsId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "Dragon")
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

        // Name match → score 40 (contains) + 15 = 40
        let nameMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Dungeon Map", itemId: nameMatchId, forceSave: false)

        // Description-only match → score 10 + 15 = 25
        let descMatchId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Random Encounter", itemId: descMatchId, forceSave: false)
        root.editController.reset(description: "A dungeon encounter table", itemId: descMatchId, forceSave: false)

        let results = await sut.globalSearchResults(searchText: "dungeon")
        let matchIds = results.map(\.itemId)

        let nameIndex = try #require(matchIds.firstIndex(of: nameMatchId))
        let descIndex = try #require(matchIds.firstIndex(of: descMatchId))

        #expect(nameIndex < descIndex)
    }
}
