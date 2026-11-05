// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// Where a photo the game master shows on the map points: the last opened room while it is
/// open, otherwise the map's center.
@Suite("Map photo anchor")
@MainActor
struct MapPhotoAnchorTests {
    private let hall = [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 400), CGPoint(x: 100, y: 400)]
    private let cellar = [CGPoint(x: 600, y: 100), CGPoint(x: 800, y: 100), CGPoint(x: 800, y: 300), CGPoint(x: 600, y: 300)]
    private let mapCenter = CGPoint(x: 600, y: 400)

    private struct Fixture {
        let controller: GameController
        let mapId: UUID
        let hallId: UUID
        let cellarId: UUID
    }

    private func makeFixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let mapId = UUID()
        let hallId = UUID()
        let cellarId = UUID()
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [
                MapEntryModel(id: hallId, name: "Hall", content: "", coordinates: hall, isShown: false),
                MapEntryModel(id: cellarId, name: "Cellar", content: "", coordinates: cellar, isShown: false)
            ],
            width: 1200,
            height: 800
        )
        root.itemController.replace(model: map, isInsert: true)
        root.gameController.setGame(item: map.copy(), itemId: mapId)
        return Fixture(controller: root.gameController, mapId: mapId, hallId: hallId, cellarId: cellarId)
    }

    @Test("A room's center is the middle of its bounding box")
    func roomCenterIsBoundsMidpoint() {
        let room = MapEntryModel(id: UUID(), name: "Hall", content: "", coordinates: hall)
        #expect(room.center == CGPoint(x: 200, y: 300))
    }

    @Test("Without an opened room the photo points at the map's center")
    func noRoomOpenedPointsAtMapCenter() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == mapCenter)
    }

    @Test("The photo points at the room opened last")
    func lastOpenedRoom() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == CGPoint(x: 200, y: 300))

        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == CGPoint(x: 700, y: 200))
    }

    @Test("Closing a room does not make it the anchor, and a closed last room falls back to the map's center")
    func closedRoomFallsBackToMapCenter() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))
        // Closing the hall is not an opening: the cellar stays the anchor.
        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.hallId))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == CGPoint(x: 700, y: 200))

        #expect(fixture.controller.toggleRoom(itemId: fixture.mapId, roomId: fixture.cellarId))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == mapCenter)
    }

    @Test("Revealing rooms together and focusing a room both count as opening")
    func showAllAndFocusRecord() async throws {
        let fixture = try await makeFixture()
        #expect(fixture.controller.setRoomsShown(
            itemId: fixture.mapId,
            roomIds: [fixture.cellarId, fixture.hallId],
            isShown: true
        ))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == CGPoint(x: 200, y: 300))

        #expect(fixture.controller.toggleRoomFocus(itemId: fixture.mapId, roomId: fixture.cellarId))
        #expect(fixture.controller.photoAnchor(for: fixture.mapId) == CGPoint(x: 700, y: 200))
    }

    @Test("The popover model shows its photo only on the map it belongs to")
    func popoverBelongsToItsMap() {
        let model = MapPhotoPopoverModel()
        let mapId = UUID()
        let photo = MapPhotoPopoverItem(photoId: UUID(), mapId: mapId, anchor: .zero)
        model.photo = photo
        #expect(model.photo(on: mapId) == photo)
        #expect(model.photo(on: UUID()) == nil)
        #expect(model.photo(on: nil) == nil)

        // Without a game's actions, Close still closes it on this device.
        model.close()
        #expect(model.photo == nil)
    }
}
#endif
