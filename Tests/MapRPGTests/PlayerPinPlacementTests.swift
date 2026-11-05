// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// The game master opening a map puts the player pins in its first room, unless they were
/// positioned on that very map. See `GameController.synchronizePlayerPins(for:)`.
@MainActor
struct PlayerPinPlacementTests {
    @Test("A pin without a position, or with another map's position, goes to the first room")
    func unpositionedAndForeignPinsGoToFirstRoom() async throws {
        let fixture = try await makeFixture()

        #expect(fixture.sut.synchronizePlayerPins(for: fixture.mapA.id))
        let pinOnA = try #require(pin(fixture.playerId, on: fixture.mapA, in: fixture.sut))
        #expect(pinOnA.location == CGPoint(x: 150, y: 150))
        #expect(pinOnA.mapId == fixture.mapA.id)

        // The pin moves on map A, then the master opens map B with its own room elsewhere.
        #expect(fixture.sut.updatePin(itemId: fixture.mapA.id, data: moved(fixture.playerId, to: CGPoint(x: 280, y: 190)), playerId: fixture.playerId))
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.mapB.id))
        let pinOnB = try #require(pin(fixture.playerId, on: fixture.mapB, in: fixture.sut))
        #expect(pinOnB.location == CGPoint(x: 550, y: 550))
        #expect(pinOnB.mapId == fixture.mapB.id)
    }

    @Test("A pin positioned on the shown map keeps its place, also after another map was shown")
    func positionedPinStaysOnItsMap() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.mapA.id))
        #expect(fixture.sut.updatePin(itemId: fixture.mapA.id, data: moved(fixture.playerId, to: CGPoint(x: 280, y: 190)), playerId: fixture.playerId))

        // Showing the same map again, with no one having moved, changes nothing.
        #expect(!fixture.sut.synchronizePlayerPins(for: fixture.mapA.id))
        #expect(pin(fixture.playerId, on: fixture.mapA, in: fixture.sut)?.location == CGPoint(x: 280, y: 190))

        // Another pin moves on map B; map A still holds the first pin where the player left it.
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.mapB.id))
        #expect(fixture.sut.updatePin(itemId: fixture.mapB.id, data: moved(fixture.playerId, to: CGPoint(x: 700, y: 600)), playerId: fixture.playerId))
        fixture.sut.synchronizePlayerPins(for: fixture.mapA.id)
        #expect(pin(fixture.playerId, on: fixture.mapA, in: fixture.sut)?.location == CGPoint(x: 280, y: 190))
        #expect(pin(fixture.playerId, on: fixture.mapB, in: fixture.sut)?.location == CGPoint(x: 700, y: 600))
    }

    @Test("A master move stamps the map, so the pin stays when the map is shown again")
    func masterMoveKeepsPlace() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.sut.synchronizePlayerPins(for: fixture.mapA.id))
        #expect(fixture.sut.movePin(itemId: fixture.mapA.id, pinId: fixture.playerId, location: CGPoint(x: 200, y: 120)))
        #expect(!fixture.sut.synchronizePlayerPins(for: fixture.mapA.id))
        #expect(pin(fixture.playerId, on: fixture.mapA, in: fixture.sut)?.location == CGPoint(x: 200, y: 120))
    }

    @Test("The map id is memory only: it is neither encoded nor decoded")
    func mapIdIsNotSerialized() throws {
        let pin = MapPinModel(id: UUID(), name: "Hero", isPlayer: true, mapId: UUID())
        let data = try #require(pin.encodeData())
        #expect(!String(decoding: data, as: UTF8.self).contains("mapId"))
        #expect(MapPinModel.decodeData(of: data)?.mapId == nil)
    }
}

private extension PlayerPinPlacementTests {
    struct Fixture {
        let sut: GameController
        let mapA: MapModel
        let mapB: MapModel
        let playerId: UUID
    }

    func makeFixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let playerId = UUID()
        let mapA = MapModel(id: UUID(), name: "A", entries: [room(origin: CGPoint(x: 100, y: 100))])
        let mapB = MapModel(id: UUID(), name: "B", entries: [room(origin: CGPoint(x: 500, y: 500))])
        sut.mapGameModel.playerPins = [MapPinModel(id: playerId, name: "Hero", isPlayer: true, players: [playerId])]
        // The game keeps one live copy per map; the session's pin reaches each when it is shown.
        sut.setGame(item: mapA, itemId: mapA.id)
        sut.setGame(item: mapB, itemId: mapB.id)
        return Fixture(sut: sut, mapA: mapA, mapB: mapB, playerId: playerId)
    }

    func room(origin: CGPoint) -> MapEntryModel {
        MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: [
            origin,
            CGPoint(x: origin.x + 200, y: origin.y),
            CGPoint(x: origin.x + 200, y: origin.y + 100),
            CGPoint(x: origin.x, y: origin.y + 100)
        ])
    }

    func moved(_ pinId: UUID, to location: CGPoint) -> Data? {
        MapPinModel(
            id: pinId,
            name: "Hero",
            location: location,
            isPlayer: true,
            players: [pinId],
            timeInterval: Date.now.timeIntervalSince1970 + 1
        ).encodeData()
    }

    func pin(_ id: UUID, on map: MapModel, in sut: GameController) -> MapPinModel? {
        sut.gameItem(for: map.id).mapPins.first { $0.id == id }
    }
}
#endif
