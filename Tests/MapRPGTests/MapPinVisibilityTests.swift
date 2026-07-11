// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

@MainActor
struct MapPinVisibilityTests {
    let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]

    @Test func entryContainsPoint() {
        let entry = MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: square)

        #expect(entry.contains(CGPoint(x: 50, y: 50)))
        #expect(!entry.contains(CGPoint(x: 150, y: 50)))
    }

    @Test func entryContainsRejectsDegeneratePolygon() {
        let entry = MapEntryModel(id: UUID(), name: "Line", content: "", coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])

        #expect(!entry.contains(CGPoint(x: 50, y: 50)))
    }

    @Test func entryContainsConcavePolygon() {
        // L-shape: the notch (upper right) is outside.
        let lShape = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        let entry = MapEntryModel(id: UUID(), name: "L", content: "", coordinates: lShape)

        #expect(entry.contains(CGPoint(x: 25, y: 25)))
        #expect(entry.contains(CGPoint(x: 75, y: 75)))
        #expect(!entry.contains(CGPoint(x: 75, y: 25)))
    }

    @Test func locationHiddenForPlayersOnlyInsideHiddenRooms() {
        let hidden = MapEntryModel(id: UUID(), name: "Hidden", content: "", coordinates: square, isShown: false)
        let shownCoordinates = square.map { CGPoint(x: $0.x + 200, y: $0.y) }
        let shown = MapEntryModel(id: UUID(), name: "Shown", content: "", coordinates: shownCoordinates, isShown: true)
        let map = MapModel(id: UUID(), name: "Dungeon", entries: [hidden, shown])

        #expect(map.isLocationHiddenForPlayers(CGPoint(x: 50, y: 50)))
        #expect(!map.isLocationHiddenForPlayers(CGPoint(x: 250, y: 50)))
        // Outside every room: no fog, visible.
        #expect(!map.isLocationHiddenForPlayers(CGPoint(x: 500, y: 500)))
    }

    @Test func movePinUpdatesGameItemAndPlayerPins() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Hero", isPlayer: true, players: [pinId], timeInterval: 1)
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        sut.mapGameModel.playerPins = [pin]

        let moved = sut.movePin(itemId: mapId, pinId: pinId, location: CGPoint(x: 42, y: 24))

        #expect(moved)
        let itemPin = sut.gameItem(for: mapId).mapPins.first { $0.id == pinId }
        #expect(itemPin?.location == CGPoint(x: 42, y: 24))
        #expect((itemPin?.timeInterval ?? 0) > 1)
        #expect(sut.mapGameModel.playerPins.first { $0.id == pinId }?.location == CGPoint(x: 42, y: 24))
    }

    @Test func togglePinFlipsVisibilityAndStampsTime() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Ogre", isShown: true, timeInterval: 1)
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.togglePin(itemId: mapId, pinId: pinId))

        let itemPin = sut.gameItem(for: mapId).mapPins.first { $0.id == pinId }
        #expect(itemPin?.isShown == false)
        #expect((itemPin?.timeInterval ?? 0) > 1)
        #expect(!sut.togglePin(itemId: mapId, pinId: UUID()))
    }

    @Test func networkPinEncodesCurrentPinState() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let pinId = UUID()
        let pin = MapPinModel(id: pinId, name: "Hero", isPlayer: true, players: [pinId])
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [pin])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        _ = sut.movePin(itemId: mapId, pinId: pinId, location: CGPoint(x: 7, y: 9))

        let data = try #require(sut.networkPin(itemId: mapId, pinId: pinId))

        #expect(data.id == mapId)
        #expect(data.type == .map)
        let decoded = try #require(MapPinModel.decodeData(of: data.data))
        #expect(decoded.id == pinId)
        #expect(decoded.location == CGPoint(x: 7, y: 9))
        #expect(sut.networkPin(itemId: mapId, pinId: UUID()) == nil)
    }

    @Test func movePinUnknownPinReturnsFalse() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon")
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(!sut.movePin(itemId: mapId, pinId: UUID(), location: .zero))
    }
}
#endif
