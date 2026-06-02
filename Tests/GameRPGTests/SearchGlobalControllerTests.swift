// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// Tests for `SearchGlobalController` — verifies that global search returns results
/// from each module and respects the player-mode filter.
@MainActor
struct SearchGlobalControllerTests {

    // MARK: - Empty search

    @Test("Empty search text clears results and returns immediately")
    func emptySearchTextClearsResults() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        let sut = SearchGlobalController(root: gameRoot, searchText: "")
        // Pre-populate to confirm the guard wipes them
        sut.model.results = [.space: []]

        await sut.performSearch()

        #expect(sut.model.results.isEmpty, "Empty search text must clear all module results")
        #expect(!sut.model.isSearching)
    }

    @Test("Non-matching search text returns empty arrays for all modules")
    func nonMatchingSearchReturnsEmpty() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        let sut = SearchGlobalController(root: gameRoot, searchText: "UNIQUE_NOMATCH_XYZ_12345")

        await sut.performSearch()

        let allResults = sut.model.results.values.flatMap { $0 }
        #expect(allResults.isEmpty, "Unrecognisable search text must return no results from any module")
    }

    // MARK: - Per-module search

    @Test("Space module — item name match appears in space results")
    func spaceModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.spaceRoot.itemController.resetData()
        let itemId = await gameRoot.spaceRoot.itemController.addNew(type: .item)
        gameRoot.spaceRoot.editController.reset(name: "Dragon Cruiser", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon Cruiser")
        await sut.performSearch()

        let results = try #require(sut.model.results[.space], "Space key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("PDF module — item name match appears in pdf results")
    func pdfModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.pdfRoot.itemController.resetData()
        let itemId = await gameRoot.pdfRoot.itemController.addNew(type: .item)
        gameRoot.pdfRoot.editController.reset(name: "Arcane Tome", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Arcane Tome")
        await sut.performSearch()

        let results = try #require(sut.model.results[.pdf], "PDF key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("Audio module — item name match appears in audio results")
    func audioModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.audioRoot.itemController.resetData()
        let itemId = await gameRoot.audioRoot.itemController.addNew(type: .item)
        gameRoot.audioRoot.editController.reset(name: "Battle Fanfare", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Battle Fanfare")
        await sut.performSearch()

        let results = try #require(sut.model.results[.audio], "Audio key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("Character module — character name match appears in value results")
    func characterModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.characterRoot.itemController.resetData()
        let itemId = await gameRoot.characterRoot.itemController.addNew(type: .item)
        gameRoot.characterRoot.editController.reset(name: "Aldric the Bold", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Aldric")
        await sut.performSearch()

        let results = try #require(sut.model.results[.value], "Character (value) key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("Photo module — item name match appears in photo results")
    func photoModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.photoRoot.itemController.resetData()
        let itemId = await gameRoot.photoRoot.itemController.addNew(type: .item)
        gameRoot.photoRoot.editController.reset(name: "Dragon Landscape", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon Landscape")
        await sut.performSearch()

        let results = try #require(sut.model.results[.photo], "Photo key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("Dice module — item name match appears in dice results")
    func diceModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.diceRoot.itemController.resetData()
        let itemId = await gameRoot.diceRoot.itemController.addNew(type: .item)
        gameRoot.diceRoot.editController.reset(name: "Dragon Dice Set", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon Dice Set")
        await sut.performSearch()

        let results = try #require(sut.model.results[.dice], "Dice key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    @Test("Table module — item name match appears in table results")
    func tableModuleItemFound() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.tableRoot.itemController.resetData()
        let itemId = await gameRoot.tableRoot.itemController.addNew(type: .item)
        gameRoot.tableRoot.editController.reset(name: "Loot Table Alpha", itemId: itemId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Loot Table Alpha")
        await sut.performSearch()

        let results = try #require(sut.model.results[.table], "Table key must be present in results")
        #expect(results.contains(where: { $0.itemId == itemId }))
    }

    // MARK: - Player-mode filter

    @Test("Player mode excludes adventure, map and weather from search")
    func playerModeExcludesAdventureMapWeather() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon")
        sut.model.playerMode = true

        await sut.performSearch()

        #expect(sut.model.results[.adventure] == nil, "Adventure must not be present in player mode")
        #expect(sut.model.results[.map] == nil,       "Map must not be present in player mode")
        #expect(sut.model.results[.weather] == nil,   "Weather must not be present in player mode")
    }

    @Test("Non-player mode always searches adventure, map and weather")
    func nonPlayerModeIncludesAdventureMapWeather() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        let sut = SearchGlobalController(root: gameRoot, searchText: "something")
        sut.model.playerMode = false

        await sut.performSearch()

        #expect(sut.model.results.keys.contains(.adventure), "Adventure key must be present in non-player mode")
        #expect(sut.model.results.keys.contains(.map),       "Map key must be present in non-player mode")
        #expect(sut.model.results.keys.contains(.weather),   "Weather key must be present in non-player mode")
    }

    // MARK: - Multi-module search

    @Test("Same search term finds items across multiple modules simultaneously")
    func searchTermFindsItemsInMultipleModules() async throws {
        let gameRoot = try await MockRoot.createGameRoot()

        await gameRoot.audioRoot.itemController.resetData()
        let audioId = await gameRoot.audioRoot.itemController.addNew(type: .item)
        gameRoot.audioRoot.editController.reset(name: "Dragon Theme", itemId: audioId)

        await gameRoot.spaceRoot.itemController.resetData()
        let spaceId = await gameRoot.spaceRoot.itemController.addNew(type: .item)
        gameRoot.spaceRoot.editController.reset(name: "Dragon Scout", itemId: spaceId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon")
        await sut.performSearch()

        let audioResults = sut.model.results[.audio] ?? []
        let spaceResults = sut.model.results[.space] ?? []
        #expect(audioResults.contains(where: { $0.itemId == audioId }), "Dragon Theme must appear in audio results")
        #expect(spaceResults.contains(where: { $0.itemId == spaceId }), "Dragon Scout must appear in space results")
    }

    // MARK: - Result relevance ordering

    @Test("Results are sorted by relevance — exact name match ranks above contains match")
    func resultsAreOrderedByRelevance() async throws {
        let gameRoot = try await MockRoot.createGameRoot()
        await gameRoot.spaceRoot.itemController.resetData()

        let exactId = await gameRoot.spaceRoot.itemController.addNew(type: .item)
        let containsId = await gameRoot.spaceRoot.itemController.addNew(type: .item)
        gameRoot.spaceRoot.editController.reset(name: "Dragon",           itemId: exactId)
        gameRoot.spaceRoot.editController.reset(name: "The Dragon Fleet", itemId: containsId)

        let sut = SearchGlobalController(root: gameRoot, searchText: "Dragon")
        await sut.performSearch()

        let results = try #require(sut.model.results[.space])
        let ids = results.map(\.itemId)
        let exactIdx    = try #require(ids.firstIndex(of: exactId))
        let containsIdx = try #require(ids.firstIndex(of: containsId))
        #expect(exactIdx < containsIdx, "Exact name match must rank above contains match")
    }
}
#endif
