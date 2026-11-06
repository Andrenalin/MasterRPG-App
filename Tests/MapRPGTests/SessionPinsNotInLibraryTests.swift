// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import MapRPG

@Suite("Session pins never reach the library")
@MainActor
struct SessionPinsNotInLibraryTests {
    private func installFilter(_ root: MapRootModel) {
        let controller = root.gameController
        root.itemController.itemDataModel.libraryWriteFilter = { model in
            (model as? MapModel).flatMap { controller.libraryCopy(of: $0) }
        }
    }

    @Test func aLibraryWriteDuringTheGameKeepsPlayerPinsAndCloneIdsOut() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        installFilter(root)
        let sut = root.gameController
        let mapId = UUID()
        let sourceId = UUID()
        let cloneId = UUID()
        let player = MapPinModel(id: UUID(), name: "Hero", isPlayer: true)
        let monster = MapPinModel(id: UUID(), name: "Orc", characterId: cloneId)
        let marker = MapPinModel(id: UUID(), name: "Door")
        root.itemController.replace(model: MapModel(id: mapId, name: "Dungeon", mapPins: [marker]), isInsert: true)
        sut.mapGameModel.registerBattleCharacterCopy(cloneId, source: sourceId)

        // The game copy, then a whole-model library write from the item editor (forceSave).
        let gameMap = MapModel(id: mapId, name: "Dungeon", mapPins: [marker, monster, player])
        sut.setGame(item: gameMap, itemId: mapId)
        root.itemController.itemDataModel.isGameMode = true
        let edited = gameMap.copy()
        edited.name = "Renamed"
        root.itemController.replace(model: edited, isInsert: false, forceSave: true)

        let library = try #require(root.itemController.itemSync(for: mapId, noGame: true))
        #expect(library.name == "Renamed")
        #expect(library.mapPins.map(\.id) == [marker.id, monster.id])
        #expect(library.mapPins.first { $0.id == monster.id }?.characterId == sourceId)
        // The running game keeps its own pins.
        #expect(gameMap.mapPins.contains { $0.isPlayer })
        #expect(gameMap.mapPins.first { $0.id == monster.id }?.characterId == cloneId)
    }

    @Test func endingTheGameScrubsALibraryInstanceThatTookSessionPins() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let sourceId = UUID()
        let cloneId = UUID()
        let player = MapPinModel(id: UUID(), name: "Hero", isPlayer: true)
        let monster = MapPinModel(id: UUID(), name: "Orc", characterId: cloneId)
        root.itemController.replace(model: MapModel(id: mapId, name: "Dungeon", mapPins: [monster, player]), isInsert: true)
        sut.mapGameModel.registerBattleCharacterCopy(cloneId, source: sourceId)

        sut.scrubLibraryMapsOfSessionContent()

        let library = try #require(root.itemController.itemSync(for: mapId, noGame: true))
        #expect(library.mapPins.map(\.id) == [monster.id])
        #expect(library.mapPins.first?.characterId == sourceId)
    }
}
#endif
