// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// The room a pin added from the game toolbar goes into: the focused room, else the room the
/// game master opened last while it is still open, else none (the pin is drawn in the first entry).
@Suite("Map new pin room")
@MainActor
struct MapNewPinRoomTests {
    private let hall = [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400), CGPoint(x: 100, y: 400)]
    private let cellar = [CGPoint(x: 600, y: 100), CGPoint(x: 800, y: 100), CGPoint(x: 800, y: 300), CGPoint(x: 600, y: 300)]
    private let cell = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20), CGPoint(x: 0, y: 20)]

    @MainActor private struct Fixture {
        let root: MapRootModel
        let mapId: UUID
        let hallId: UUID
        let cellarId: UUID
        let cellId: UUID

        var controller: GameController { root.gameController }
    }

    private func makeFixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let mapId = UUID()
        let hallId = UUID()
        let cellarId = UUID()
        let cellId = UUID()
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [
                MapEntryModel(id: hallId, name: "Hall", content: "", coordinates: hall, isShown: false),
                MapEntryModel(id: cellarId, name: "Cellar", content: "", coordinates: cellar, isShown: false),
                MapEntryModel(id: cellId, name: "Cell", content: "", coordinates: cell, isHexGrid: true, isShown: false)
            ],
            width: 1200,
            height: 800,
            pinScale: 1
        )
        root.itemController.replace(model: map, isInsert: true)
        root.gameController.setGame(item: map.copy(), itemId: mapId)
        return Fixture(root: root, mapId: mapId, hallId: hallId, cellarId: cellarId, cellId: cellId)
    }

    @Test("A focused room wins over the room opened last")
    func focusedRoomWins() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))

        let target = fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: fixture.hallId)

        #expect(target == fixture.hallId)
    }

    @Test("Without a focused room the room opened last is the target")
    func lastOpenedRoomIsTheTarget() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == fixture.hallId)

        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == fixture.cellarId)
    }

    @Test("Focusing a room counts as opening it")
    func focusingCountsAsOpening() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.setRoomsShown(
            itemId: fixture.mapId,
            roomIds: [fixture.cellarId, fixture.hallId],
            isShown: true
        ))
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == fixture.hallId)
        #expect(fixture.controller.toggleRoomFocus(itemId: fixture.mapId, roomId: fixture.cellarId))

        // The focus flag is not passed in here, as when the toolbar has none: the last opened room is.
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == fixture.cellarId)
    }

    @Test("No room opened yet, or the last opened room closed again, leaves the pin unplaced")
    func noOpenRoomHasNoTarget() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == nil)

        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == nil)
    }

    @Test("A hex cell opened last is not a room for pins")
    func hexCellIsNotATarget() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellId))

        #expect(fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil) == nil)
    }

    @Test("Pins added with the target room stand inside the room opened last")
    func addedPinsStandInTheLastOpenedRoom() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))
        let map = fixture.controller.gameItem(for: fixture.mapId)

        fixture.root.editController.addPhotoPins(
            map: map,
            entryId: fixture.controller.newPinRoomId(itemId: fixture.mapId, focusedRoomId: nil),
            location: nil,
            photoIds: [UUID(), UUID()]
        )

        let cellarBounds = CGRect(x: 600, y: 100, width: 200, height: 200)
        #expect(map.mapPins.count == 2)
        #expect(map.mapPins.allSatisfy { cellarBounds.contains($0.location) })
    }
}
#endif
