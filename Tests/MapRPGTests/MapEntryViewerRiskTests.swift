// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

/// CODE_AUDIT_26 §10.14: the room lookup next to a hex grid, the needle insert at the wrap and a
/// coarse guard for resetting thousands of cells.
@Suite("Map entry viewer risks")
@MainActor
struct MapEntryViewerRiskTests {
    private func square(_ origin: CGPoint, side: CGFloat) -> [CGPoint] {
        [
            origin,
            CGPoint(x: origin.x + side, y: origin.y),
            CGPoint(x: origin.x + side, y: origin.y + side),
            CGPoint(x: origin.x, y: origin.y + side)
        ]
    }

    private func makeSession() -> MapEditorSession {
        MapEditorSession(
            map: .previewEmpty,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            mapMode: .gameMaster
        )
    }

    // MARK: - Hex grid and room

    @Test("A point inside a room on a hex map finds the room, not the hex cell")
    func roomWinsOverHexCell() {
        let session = makeSession()
        let room = MapEntryModel(id: UUID(), name: "Hall", content: "", coordinates: square(CGPoint(x: 100, y: 100), side: 100))
        let cell = MapEntryModel(id: UUID(), name: "Cell", content: "", coordinates: square(.zero, side: 400), isHexGrid: true)
        session.entries.resetEntries(mapId: UUID(), entries: [room, cell])

        #expect(session.entry(for: CGPoint(x: 150, y: 150), in: .previewEmpty)?.id == room.id)
    }

    @Test("A point on a hex cell outside every room finds no entry")
    func hexCellAloneIsNoRoom() {
        let session = makeSession()
        let room = MapEntryModel(id: UUID(), name: "Hall", content: "", coordinates: square(CGPoint(x: 100, y: 100), side: 100))
        let cell = MapEntryModel(id: UUID(), name: "Cell", content: "", coordinates: square(.zero, side: 400), isHexGrid: true)
        session.entries.resetEntries(mapId: UUID(), entries: [room, cell])

        #expect(session.entry(for: CGPoint(x: 350, y: 350), in: .previewEmpty) == nil)
    }

    @Test("Where rooms overlap the topmost one wins")
    func topmostRoomWins() {
        let session = makeSession()
        let lower = MapEntryModel(id: UUID(), name: "Lower", content: "", coordinates: square(.zero, side: 200))
        let upper = MapEntryModel(id: UUID(), name: "Upper", content: "", coordinates: square(CGPoint(x: 50, y: 50), side: 100))
        session.entries.resetEntries(mapId: UUID(), entries: [lower, upper])

        #expect(session.entry(for: CGPoint(x: 100, y: 100), in: .previewEmpty)?.id == upper.id)
        #expect(session.entry(for: CGPoint(x: 10, y: 10), in: .previewEmpty)?.id == lower.id)
    }

    // MARK: - Needle insert

    private func needle(_ viewer: MapEntryViewerModel, entryId: UUID, index: Int) throws -> MapNeedlePointModel {
        try #require(viewer.renderedNeedlePoints(for: entryId).first { $0.coordinateIndex == index })
    }

    @Test("Inserting after the last point puts the midpoint to the first point at the end")
    func insertAfterLastPointUsesWrapMidpoint() throws {
        let entryId = UUID()
        let corners = square(.zero, side: 10)
        let viewer = MapEntryViewerModel(mapId: UUID(), entries: [MapEntryModel(id: entryId, name: "Room", content: "", coordinates: corners)])

        viewer.insertNeedle(after: try needle(viewer, entryId: entryId, index: 3), entryId: entryId)

        let coordinates = viewer.entry(entryId).coordinates
        #expect(coordinates.count == 5)
        #expect(Array(coordinates.prefix(4)) == corners)
        #expect(coordinates[4] == CGPoint(x: 0, y: 5))
        #expect(viewer.renderedNeedlePoints(for: entryId).count == 5)
    }

    @Test("Inserting between two points puts the midpoint after the chosen point and shifts later indices")
    func insertInTheMiddleShiftsLaterPoints() throws {
        let entryId = UUID()
        let viewer = MapEntryViewerModel(mapId: UUID(), entries: [MapEntryModel(id: entryId, name: "Room", content: "", coordinates: square(.zero, side: 10))])
        let laterPoint = try needle(viewer, entryId: entryId, index: 2)

        viewer.insertNeedle(after: try needle(viewer, entryId: entryId, index: 0), entryId: entryId)

        let coordinates = viewer.entry(entryId).coordinates
        #expect(coordinates[1] == CGPoint(x: 5, y: 0))
        #expect(coordinates[3] == CGPoint(x: 10, y: 10))
        #expect(laterPoint.coordinateIndex == 3)
        #expect(Set(viewer.renderedNeedlePoints(for: entryId).map(\.coordinateIndex)) == [0, 1, 2, 3, 4])
    }

    // MARK: - Thousands of cells

    @Test("Resetting thousands of cells completes and keeps every lookup", .timeLimit(.minutes(1)))
    func resetWithThousandsOfCells() {
        let cells = (0..<4_000).map { index in
            MapEntryModel(
                id: UUID(),
                name: "Cell \(index)",
                content: "",
                coordinates: square(CGPoint(x: CGFloat(index % 80) * 10, y: CGFloat(index / 80) * 10), side: 10),
                isHexGrid: true
            )
        }
        let viewer = MapEntryViewerModel(mapId: UUID(), tracksNeedles: false)

        viewer.resetEntries(mapId: UUID(), entries: cells)
        viewer.resetEntries(mapId: UUID(), entries: cells)

        #expect(viewer.entries.count == 4_000)
        #expect(viewer.roomNodes.count == 4_000)
        #expect(viewer.entry(cells[3_999].id).name == "Cell 3999")
        #expect(viewer.roomNode(for: cells[2_000].id) != nil)
    }
}
#endif
