// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import MapRPG

@Suite("Who may move a player pin")
@MainActor
struct PlayerPinControllersTests {
    @Test func aPlayerPinMovesForItsPlayerAndTheListedDevices() {
        let ownerId = UUID()
        let delegateId = UUID()
        let pin = MapPinModel(id: ownerId, name: "Hero", isPlayer: true, players: [ownerId, delegateId])

        #expect(pin.isControlled(by: ownerId))
        #expect(pin.isControlled(by: delegateId))
        #expect(!pin.isControlled(by: UUID()))
        #expect(!pin.isControlled(by: nil))

        var monster = pin
        monster.isPlayer = false
        #expect(!monster.isControlled(by: delegateId))
    }

    @Test func controllersReachEveryMapAndSurviveTheCharacterHandshake() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon")
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        let playerId = UUID()
        let observerId = UUID()
        let characterId = UUID()
        root.characterRoot.itemController.replace(model: ValueModel(id: characterId, name: "Hero"), isInsert: true)

        sut.resetPlayerPins(for: [PlayerGameModel(id: playerId, type: .player, name: "Anna", characterId: characterId)])
        #expect(sut.setPlayerPinControllers([playerId: [observerId, playerId]]))
        #expect(sut.gameItem(for: mapId).mapPins.first { $0.id == playerId }?.players == [playerId, observerId])
        #expect(sut.mapGameModel.playerPins.first { $0.id == playerId }?.players == [playerId, observerId])
        #expect(!sut.setPlayerPinControllers([playerId: [observerId]]))

        // The Character package arriving later rewrites the pin's metadata, not its controllers.
        sut.setPlayerPin(for: playerId, name: "Anna", characterId: characterId)
        #expect(sut.gameItem(for: mapId).mapPins.first { $0.id == playerId }?.players == [playerId, observerId])

        #expect(sut.setPlayerPinControllers([:]))
        #expect(sut.gameItem(for: mapId).mapPins.first { $0.id == playerId }?.players == [playerId])
    }
}
#endif
