// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@Suite("Pencil room drawing")
struct MapPencilStrokeTests {
    /// A wobbly square outline sampled every 2 points, starting and ending near the top left.
    private func squareStroke(side: CGFloat = 200, jitter: CGFloat = 1) -> MapPencilStroke {
        var stroke = MapPencilStroke()
        let corners = [
            CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0),
            CGPoint(x: side, y: side), CGPoint(x: 0, y: side), CGPoint(x: 3, y: 3)
        ]
        for (start, end) in zip(corners, corners.dropFirst()) {
            let steps = Int(hypot(end.x - start.x, end.y - start.y) / 2)
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                let wobble = step.isMultiple(of: 2) ? jitter : -jitter
                stroke.append(CGPoint(
                    x: start.x + (end.x - start.x) * t + wobble,
                    y: start.y + (end.y - start.y) * t - wobble
                ))
            }
        }
        return stroke
    }

    @Test("A wobbly square outline becomes about four corners")
    func squareSimplifiesToItsCorners() throws {
        let polygon = try #require(squareStroke().polygon(scale: 1))

        #expect((4...6).contains(polygon.count))
        let bounds = try #require(polygon.bounds)
        #expect(abs(bounds.width - 200) < 8)
        #expect(abs(bounds.height - 200) < 8)
    }

    @Test("The closing sample next to the start is not kept as a point of its own")
    func closingSampleIsDropped() throws {
        let polygon = try #require(squareStroke().polygon(scale: 1))

        let first = try #require(polygon.first)
        let last = try #require(polygon.last)
        #expect(hypot(first.x - last.x, first.y - last.y) > MapPencilStroke.screenTolerance)
    }

    @Test("Zooming in keeps more detail of the same stroke")
    func toleranceFollowsTheZoom() throws {
        var stroke = MapPencilStroke()
        for index in 0...120 {
            let angle = Double(index) / 120 * 2 * .pi
            stroke.append(CGPoint(x: 100 + 100 * cos(angle), y: 100 + 100 * sin(angle)))
        }

        let zoomedOut = try #require(stroke.polygon(scale: 0.5))
        let zoomedIn = try #require(stroke.polygon(scale: 4))

        #expect(zoomedIn.count > zoomedOut.count)
    }

    @Test("A tap, a short line and a scribble are not rooms")
    func tinyStrokesAreRejected() {
        var dot = MapPencilStroke()
        dot.append(CGPoint(x: 10, y: 10))
        dot.append(CGPoint(x: 11, y: 10))
        #expect(dot.polygon(scale: 1) == nil)

        var line = MapPencilStroke()
        for x in stride(from: 0, through: 300, by: 3) {
            line.append(CGPoint(x: CGFloat(x), y: 0))
        }
        #expect(line.polygon(scale: 1) == nil)

        var tiny = MapPencilStroke()
        for index in 0..<40 {
            let angle = Double(index) / 40 * 2 * .pi
            tiny.append(CGPoint(x: 5 * cos(angle), y: 5 * sin(angle)))
        }
        #expect(tiny.polygon(scale: 1) == nil)
    }

    @Test("Samples closer than the minimum distance and non-finite samples are dropped")
    func sampleFiltering() {
        var stroke = MapPencilStroke()
        let first = stroke.append(CGPoint(x: 0, y: 0), minimumDistance: 5)
        let tooClose = stroke.append(CGPoint(x: 1, y: 1), minimumDistance: 5)
        let notFinite = stroke.append(CGPoint(x: CGFloat.nan, y: 0))
        let far = stroke.append(CGPoint(x: 20, y: 0), minimumDistance: 5)
        #expect(first)
        #expect(!tooClose)
        #expect(!notFinite)
        #expect(far)
        #expect(stroke.points.count == 2)
    }

    @Test("A long stroke does not overflow the stack")
    func longStrokeIsSimplified() {
        let points = (0..<50_000).map { CGPoint(x: CGFloat($0) * 0.01, y: sin(CGFloat($0) * 0.01) * 50) }
        let simplified = MapPencilStroke.simplified(points, tolerance: 1)
        #expect(simplified.count < points.count)
        #expect(simplified.first == points.first)
        #expect(simplified.last == points.last)
    }
}

@MainActor
@Suite("Pencil room drawing in the editor", .serialized)
struct MapPencilRoomEditorTests {
    private let polygon = [
        CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10),
        CGPoint(x: 110, y: 90), CGPoint(x: 10, y: 90)
    ]

    @Test("A stroke replaces the shape of the room being edited, as one undo step")
    func replacesActiveRoom() throws {
        let entry = MapEntryModel(
            id: UUID(), name: "Cellar", content: "",
            coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 5)]
        )
        let context = makeContext(entries: [entry], activeEntryId: entry.id)

        let applied = context.controller.applyPencilRoom(polygon, editorModel: context.session)

        #expect(applied)
        #expect(context.session.editEntries.entries.first?.coordinates == polygon)
        #expect(context.session.workingCopy?[entry.id].coordinates == polygon)
        #expect(context.session.workingCopy?.entries.count == 1)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?[entry.id].coordinates == entry.coordinates)
    }

    @Test("Without a room being edited a stroke creates a new room and selects it")
    func createsNewRoom() throws {
        let context = makeContext(entries: [], activeEntryId: nil)

        #expect(context.controller.applyPencilRoom(polygon, editorModel: context.session))

        let created = try #require(context.session.workingCopy?.entries.first)
        #expect(created.coordinates == polygon)
        #expect(context.session.editEntries.entries.first?.id == created.id)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?.entries.isEmpty == true)
    }

    @Test("A polygon with fewer than three points is ignored")
    func rejectsDegeneratePolygon() {
        let context = makeContext(entries: [], activeEntryId: nil)

        #expect(!context.controller.applyPencilRoom(Array(polygon.prefix(2)), editorModel: context.session))
        #expect(context.session.workingCopy?.entries.isEmpty == true)
    }

    @Test("A finished stroke is routed through the session and cleared")
    func finishedStrokeClearsState() {
        let context = makeContext(entries: [], activeEntryId: nil)
        context.session.isPencilDrawing = true
        context.session.pencilStroke.append(CGPoint(x: 1, y: 1))
        context.session.pencilStrokeOrigin = CGPoint(x: 1, y: 1)

        context.session.finishPencilStroke()

        #expect(context.session.pencilStroke.isEmpty)
        #expect(context.session.pencilStrokeOrigin == nil)
    }

    @Test("Draw mode turns off with a cleared stroke")
    func turningOffClearsStroke() {
        let context = makeContext(entries: [], activeEntryId: nil)
        context.session.isPencilDrawing = true
        context.session.pencilStroke.append(CGPoint(x: 1, y: 1))

        context.session.setPencilDrawing(false)

        #expect(!context.session.isPencilDrawing)
        #expect(context.session.pencilStroke.isEmpty)
    }

    @Test("Room hit targets step aside while the pencil draws")
    func hitTargetsDisabledWhileDrawing() {
        let context = makeContext(entries: [], activeEntryId: nil)
        #expect(context.session.roomHitTargetsAreEnabled)

        context.session.isPencilDrawing = true

        #expect(!context.session.roomHitTargetsAreEnabled)
    }

    @Test("The player display mode is read-only: no new outline point, no pencil room")
    func playerDisplayModeDoesNotEditOutline() throws {
        let entry = MapEntryModel(
            id: UUID(), name: "Cellar", content: "",
            coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5), CGPoint(x: 0, y: 5)]
        )
        let context = makeContext(entries: [entry], activeEntryId: entry.id)
        let root = MapRootModel.preview
        context.session.installActionRouter(MapEditorActionRouter(
            session: context.session,
            editController: root.editController,
            mapEditController: context.controller,
            map: try #require(context.session.workingCopy),
            root: root
        ))

        // In the game master display mode a tap adds a point.
        context.session.route(.canvasTap(CGPoint(x: 200, y: 200)))
        #expect(context.session.editEntries.entries.first?.coordinates.count == 4)

        // Master -> player.
        #expect(context.session.displayModeAnnouncement == nil)
        context.session.toggleDisplayMode()
        #expect(context.session.displayMode == .player)
        #expect(context.session.displayModeAnnouncement?.mode == .player)
        #expect(!context.session.canEditRoomOutline)
        context.session.route(.canvasTap(CGPoint(x: 220, y: 220)))
        context.session.route(.pencilRoom(polygon))

        #expect(context.session.editEntries.entries.first?.coordinates.count == 4)
        #expect(context.session.workingCopy?[entry.id].coordinates.count == 4)

        // Player -> viewer edits again.
        context.session.toggleDisplayMode()
        #expect(context.session.canEditRoomOutline)
        context.session.route(.canvasTap(CGPoint(x: 220, y: 220)))
        #expect(context.session.editEntries.entries.first?.coordinates.count == 5)
    }

    private struct Context {
        let controller: MapEditController
        let session: MapEditorSession
    }

    private func makeContext(entries: [MapEntryModel], activeEntryId: UUID?) -> Context {
        let map = MapModel(
            id: UUID(),
            name: "Pencil Test Map",
            entries: entries,
            displayConfig: DisplayConfigModel(
                id: UUID(),
                tileCoordinates: [],
                border: DisplayBorderViewModel(id: UUID())
            ),
            width: 400,
            height: 400,
            mapPins: []
        )
        let root = MapRootModel.previewFixture(models: [map])
        root.editController.setCurrentItem(model: map)
        root.editController.editorModel.sheetEditorModel.entryId = activeEntryId
        let controller = MapEditController(editController: root.editController)
        let session = MapEditorSession(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 400),
            configuration: MapEditorConfiguration(mode: .edit, displayMode: .master)
        )
        controller.prepareWorkingCopy(from: map, editorModel: session)
        session.resetEntries(newEntries: map.entries, map: map, appliesFocus: false)
        controller.changeMap(map: map, currentEntryId: activeEntryId, editorModel: session)
        return Context(controller: controller, session: session)
    }
}
#endif
