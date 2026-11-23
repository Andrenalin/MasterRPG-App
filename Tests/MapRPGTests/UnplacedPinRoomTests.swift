// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_28 §5.6: a pin without a location is drawn in the map's first room, but the player
/// rules judged its raw location (the origin), outside every room.
@MainActor
struct UnplacedPinRoomTests {
    private let square = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200)]

    private func map(firstRoomShown: Bool) -> (map: MapModel, first: MapEntryModel, second: MapEntryModel, pin: MapPinModel) {
        let first = MapEntryModel(id: UUID(), name: "Crypt", content: "", coordinates: square, isShown: firstRoomShown)
        let second = MapEntryModel(id: UUID(), name: "Hall", content: "", coordinates: square.map { CGPoint(x: $0.x + 300, y: $0.y) }, isShown: true)
        let pin = MapPinModel(id: UUID(), name: "Ogre", characterId: UUID(), location: .zero)
        return (MapModel(id: UUID(), name: "Dungeon", entries: [first, second], mapPins: [pin]), first, second, pin)
    }

    @Test("An unplaced pin in a hidden first room is not sent to players")
    func hiddenFirstRoomHidesUnplacedPin() {
        let fixture = map(firstRoomShown: false)

        #expect(!fixture.map.isPinVisibleToPlayers(fixture.pin))
    }

    @Test("An unplaced pin in a revealed first room is sent")
    func revealedFirstRoomShowsUnplacedPin() {
        let fixture = map(firstRoomShown: true)

        #expect(fixture.map.isPinVisibleToPlayers(fixture.pin))
    }

    @Test("An unplaced pin belongs to the first room for the battle, and to no other")
    func unplacedPinIsInFirstRoomOnly() {
        let fixture = map(firstRoomShown: true)

        #expect(fixture.map.isPin(fixture.pin, in: fixture.first))
        #expect(!fixture.map.isPin(fixture.pin, in: fixture.second))
    }
}
#endif
