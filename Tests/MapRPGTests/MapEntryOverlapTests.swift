// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import Testing
@testable import MapRPG

/// Hex-cell reveal by polygon overlap (CODE_AUDIT_29 §6.2) and the shared default room of the
/// pin placement (§5.15).
@MainActor
@Suite("Map room overlap and default room")
struct MapEntryOverlapTests {
    private static func room(_ points: [(CGFloat, CGFloat)], isHexGrid: Bool = false, isShown: Bool = false) -> MapEntryModel {
        MapEntryModel(
            id: UUID(),
            name: "",
            content: "",
            coordinates: points.map { CGPoint(x: $0.0, y: $0.1) },
            isHexGrid: isHexGrid,
            isShown: isShown
        )
    }

    private static let room = room([(0, 0), (100, 0), (100, 100), (0, 100)])

    @Test("A cell crossing the room border overlaps it")
    func crossingOverlaps() {
        let cell = Self.room([(90, 40), (110, 40), (110, 60), (90, 60)], isHexGrid: true)
        #expect(cell.overlaps(Self.room))
        #expect(Self.room.overlaps(cell))
    }

    @Test("A cell inside the room overlaps it, and a room inside a cell too")
    func containmentOverlaps() {
        let inner = Self.room([(40, 40), (60, 40), (60, 60), (40, 60)])
        #expect(inner.overlaps(Self.room))
        #expect(Self.room.overlaps(inner))
    }

    @Test("A cell that exactly fills the room overlaps it")
    func identicalOverlaps() {
        let same = Self.room([(0, 0), (100, 0), (100, 100), (0, 100)], isHexGrid: true)
        #expect(same.overlaps(Self.room))
    }

    @Test("Cells that only touch the border or lie outside do not overlap")
    func touchingAndDisjoint() {
        let touching = Self.room([(100, 0), (120, 0), (120, 20), (100, 20)], isHexGrid: true)
        let outside = Self.room([(200, 200), (220, 200), (220, 220), (200, 220)], isHexGrid: true)
        #expect(!touching.overlaps(Self.room))
        #expect(!outside.overlaps(Self.room))
    }

    @Test("The default room prefers a shown room over a shown hex cell over hidden rooms")
    func defaultRoomOrder() {
        let hiddenRoom = Self.room([(0, 0), (10, 0), (10, 10)])
        let shownCell = Self.room([(0, 0), (10, 0), (10, 10)], isHexGrid: true, isShown: true)
        let shownRoom = Self.room([(0, 0), (20, 0), (20, 20)], isShown: true)
        let empty = Self.room([], isShown: true)

        let all = MapModel(id: UUID(), name: "Map", entries: [empty, hiddenRoom, shownCell, shownRoom], mapPins: [])
        #expect(MapPinPlacement.defaultRoom(in: all)?.id == shownRoom.id)

        let cellOnly = MapModel(id: UUID(), name: "Map", entries: [hiddenRoom, shownCell], mapPins: [])
        #expect(MapPinPlacement.defaultRoom(in: cellOnly)?.id == shownCell.id)

        let hiddenOnly = MapModel(id: UUID(), name: "Map", entries: [empty, hiddenRoom], mapPins: [])
        #expect(MapPinPlacement.defaultRoom(in: hiddenOnly)?.id == hiddenRoom.id)

        let none = MapModel(id: UUID(), name: "Map", entries: [empty], mapPins: [])
        #expect(MapPinPlacement.defaultRoom(in: none) == nil)
    }
}
