// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor undo and redo", .serialized)
struct MapEditorUndoTests {
    @Test("Pin move, visibility, size, state, photo, copy, and removal share one history")
    func pinMutationsUndoInChronologicalOrder() throws {
        // Given
        let pinId = UUID()
        let original = MapPinModel(id: pinId, name: "Hero")
        let map = makeMap(pins: [original])
        let context = makeContext(map: map)

        // When: move
        var moved = original
        moved.location = CGPoint(x: 80, y: 40)
        context.controller.updatePinMove(pin: moved, editorModel: context.session)

        // When: visibility
        context.controller.togglePinVisibility(pinId: pinId, editorModel: context.session)

        // When: size
        context.session.pins.resizePin(id: pinId)
        context.controller.commitPinMutation(editorModel: context.session)

        // When: dead state
        context.session.pins.toggleDeadPin(id: pinId)
        context.controller.commitPinMutation(editorModel: context.session)

        // When: photo
        let photoId = UUID()
        context.session.pins.replacePhoto(pinId: pinId, itemId: photoId)
        context.controller.commitPinMutation(editorModel: context.session)

        // When: copy and remove the original
        context.session.pins.copyPin(id: pinId)
        context.controller.commitPinMutation(editorModel: context.session)
        let copiedId = try #require(
            context.session.pins.mapPins.first(where: { $0.id != pinId })?.id
        )
        context.session.pins.removePin(id: pinId)
        context.controller.commitPinMutation(editorModel: context.session)

        // Then: undo removal, copy, photo, dead, resize, visibility, and move
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.contains(where: { $0.id == pinId }))
        #expect(context.controller.undo(editorModel: context.session))
        #expect(!context.session.pins.mapPins.contains(where: { $0.id == copiedId }))
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.first?.photoId == nil)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.first?.isDead == false)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.first?.size == .normal)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.first?.isShown == true)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pins.mapPins.first?.location == .zero)

        // Then: redo the complete sequence
        for _ in 0..<7 {
            #expect(context.controller.redo(editorModel: context.session))
        }
        #expect(context.session.pins.mapPins.count == 1)
        #expect(context.session.pins.mapPins.first?.id == copiedId)
        #expect(context.session.workingCopy?.mapPins == context.session.pins.mapPins)
    }

    @Test("Room point add, move, insertion, and removal are undoable")
    func roomCoordinateMutationsAreUndoable() throws {
        // Given
        let entry = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 90, y: 10),
                CGPoint(x: 90, y: 90)
            ]
        )
        let map = makeMap(entries: [entry])
        let context = makeContext(map: map, activeEntryId: entry.id)

        // When: canvas point
        context.controller.releaseAction(
            at: CGPoint(x: 40, y: 40),
            map: map,
            editorModel: context.session,
            hasEditableEntry: true
        )
        let countAfterCanvasPoint = context.session.editEntries.entry(entry.id).coordinates.count

        // When: move point
        let point = try #require(
            context.session.editEntries.renderedNeedlePoints(for: entry.id).first
        )
        context.session.editEntries.moveNeedle(
            point,
            to: CGPoint(x: 20, y: 30),
            entryId: entry.id
        )
        context.controller.commitEntryCoordinates(
            entryId: entry.id,
            editorModel: context.session
        )

        // When: insert and remove point
        context.session.editEntries.insertNeedle(after: point, entryId: entry.id)
        context.controller.commitEntryCoordinates(
            entryId: entry.id,
            editorModel: context.session
        )
        let countAfterInsertion = context.session.editEntries.entry(entry.id).coordinates.count
        context.session.editEntries.removeNeedle(point, entryId: entry.id)
        context.controller.commitEntryCoordinates(
            entryId: entry.id,
            editorModel: context.session
        )

        // Then
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.editEntries.entry(entry.id).coordinates.count == countAfterInsertion)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.editEntries.entry(entry.id).coordinates.count == countAfterCanvasPoint)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.editEntries.entry(entry.id).coordinates.first == CGPoint(x: 10, y: 10))
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.editEntries.entry(entry.id).coordinates == entry.coordinates)
    }

    @Test("Tile points undo and redo in the tile editor")
    func tileCoordinatesAreUndoable() {
        // Given
        let original = CGPoint(x: 10, y: 20)
        let map = makeMap(tileCoordinates: [original])
        let context = makeContext(map: map, isTileEditor: true)
        let added = CGPoint(x: 30, y: 40)

        // When
        context.controller.addTileCoordinateFromCanvas(
            added,
            editorModel: context.session
        )

        // Then
        #expect(context.session.workingCopy?.displayConfig.tileCoordinates == [original, added])
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.editEntries.entries.first?.coordinates == [original])
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.session.editEntries.entries.first?.coordinates == [original, added])
    }

    @Test("Room visibility and focus undo without touching the saved model")
    func roomPresentationMutationsAreUndoable() {
        // Given
        let first = MapEntryModel(
            id: UUID(),
            name: "First",
            content: "",
            coordinates: rectangle(origin: .zero)
        )
        let second = MapEntryModel(
            id: UUID(),
            name: "Second",
            content: "",
            coordinates: rectangle(origin: CGPoint(x: 120, y: 0))
        )
        let map = makeMap(entries: [first, second])
        let context = makeContext(map: map)

        // When
        #expect(
            context.controller.toggleRoomVisibility(
                entryId: first.id,
                editorModel: context.session
            )
        )
        #expect(
            context.controller.toggleRoomFocus(
                entryId: second.id,
                editorModel: context.session
            )
        )

        // Then
        #expect(map[first.id].isShown == first.isShown)
        #expect(context.session.workingCopy?[first.id].isShown != first.isShown)
        #expect(context.session.workingCopy?[second.id].focused == true)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?[second.id].focused == false)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?[first.id].isShown == first.isShown)
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.session.focusId == second.id)
    }

    @Test("Hex grid toggle and scale are undoable")
    func hexGridMutationsAreUndoable() {
        // Given
        let map = makeMap()
        let context = makeContext(map: map)

        // When
        context.controller.toggleHexMap(editorModel: context.session)
        let initialHexScale = context.session.hexScale
        context.controller.updateHexScale(
            initialHexScale + 10,
            editorModel: context.session
        )
        context.controller.commitHexScale(editorModel: context.session)

        // Then
        #expect(context.session.workingCopy?.entries.contains(where: \.isHexGrid) == true)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.hexScale == initialHexScale)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?.entries.contains(where: \.isHexGrid) == false)
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.session.hexScale == initialHexScale + 10)
    }

    @Test("Room bounds and pin scale undo in chronological order")
    func scaleMutationsAreUndoable() throws {
        // Given
        let entry = MapEntryModel(
            id: UUID(),
            name: "Oversized",
            content: "",
            coordinates: [
                CGPoint(x: 200, y: 100),
                CGPoint(x: 200, y: 200),
                CGPoint(x: 100, y: 200)
            ]
        )
        let pin = MapPinModel(
            id: UUID(),
            name: "Pin",
            location: CGPoint(x: 200, y: 200)
        )
        let map = makeMap(entries: [entry], pins: [pin], width: 100, height: 100)
        let context = makeContext(map: map, activeEntryId: entry.id)

        // When
        context.session.maxWidthRatio = 0.5
        context.controller.updateMaxWidth(0.5, editorModel: context.session)
        context.controller.commitBoundaryScale(editorModel: context.session)
        let widthScaled = try #require(
            context.session.workingCopy?[entry.id].coordinates.map(\.x).max()
        )

        context.session.maxHeightRatio = 0.5
        context.controller.updateMaxHeight(0.5, editorModel: context.session)
        context.controller.commitBoundaryScale(editorModel: context.session)
        let heightScaled = try #require(
            context.session.workingCopy?[entry.id].coordinates.map(\.y).max()
        )

        context.session.pinScale = 2
        context.controller.updatePinScale(2, editorModel: context.session)

        // Then
        #expect(widthScaled == 50)
        #expect(heightScaled == 50)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.pinScale == 1)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?[entry.id].coordinates.map(\.y).max() == 200)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?[entry.id].coordinates.map(\.x).max() == 200)
    }

    @Test("Room bounds scaling moves the cover tile with the rooms and undoes with them")
    func boundaryScaleMovesCoverTile() throws {
        // Given
        let entry = MapEntryModel(
            id: UUID(),
            name: "Oversized",
            content: "",
            coordinates: [CGPoint(x: 200, y: 100), CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200)]
        )
        let tile = [
            CGPoint(x: 100, y: 40),
            CGPoint(x: 200, y: 40),
            CGPoint(x: 200, y: 80),
            CGPoint(x: 100, y: 80)
        ]
        let map = makeMap(entries: [entry], tileCoordinates: tile, width: 100, height: 100)
        let context = makeContext(map: map, activeEntryId: entry.id)

        // When
        context.controller.updateMaxWidth(0.5, editorModel: context.session)
        context.controller.commitBoundaryScale(editorModel: context.session)

        // Then — x halves like the rooms (200 -> 50 is a factor of 0.25), y stays
        let scaled = try #require(context.session.workingCopy?.displayConfig.tileCoordinates)
        #expect(scaled.map(\.x) == [25, 50, 50, 25])
        #expect(scaled.map(\.y) == [40, 40, 80, 80])
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?.displayConfig.tileCoordinates == tile)
    }

    @Test("Adding a room restores its selection on redo")
    func addingEntryIsUndoable() throws {
        // Given
        let map = makeMap()
        let context = makeContext(map: map)

        // When
        let entryId = try #require(
            context.controller.addEntry(editorModel: context.session)
        )

        // Then
        #expect(context.session.workingCopy?.entries.contains(where: { $0.id == entryId }) == true)
        #expect(context.controller.undo(editorModel: context.session))
        #expect(context.session.workingCopy?.entries.contains(where: { $0.id == entryId }) == false)
        #expect(context.controller.redo(editorModel: context.session))
        #expect(context.session.workingCopy?.entries.contains(where: { $0.id == entryId }) == true)
        #expect(context.session.editEntries.entries.first?.id == entryId)
    }
}

@MainActor
private extension MapEditorUndoTests {
    struct Context {
        let controller: MapEditController
        let session: MapEditorSession
    }

    func makeContext(
        map: MapModel,
        activeEntryId: UUID? = nil,
        isTileEditor: Bool = false
    ) -> Context {
        let root = MapRootModel.previewFixture(models: [map])
        root.editController.setCurrentItem(model: map)
        root.editController.editorModel.sheetEditorModel.entryId = activeEntryId
        let controller = MapEditController(editController: root.editController)
        let session = MapEditorSession(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 400),
            configuration: MapEditorConfiguration(
                mode: .edit,
                displayMode: .master,
                isTileEditor: isTileEditor
            )
        )

        if isTileEditor {
            controller.prepareTileWorkingCopy(from: map, editorModel: session)
        } else {
            controller.prepareWorkingCopy(from: map, editorModel: session)
            session.resetEntries(newEntries: map.entries, map: map, appliesFocus: false)
            controller.changeMap(
                map: map,
                currentEntryId: activeEntryId,
                editorModel: session
            )
        }
        return Context(controller: controller, session: session)
    }

    func makeMap(
        entries: [MapEntryModel] = [],
        pins: [MapPinModel] = [],
        tileCoordinates: [CGPoint] = [],
        width: CGFloat = 400,
        height: CGFloat = 400
    ) -> MapModel {
        MapModel(
            id: UUID(),
            name: "Undo Test Map",
            entries: entries,
            displayConfig: DisplayConfigModel(
                id: UUID(),
                tileCoordinates: tileCoordinates,
                border: DisplayBorderViewModel(id: UUID())
            ),
            width: width,
            height: height,
            mapPins: pins
        )
    }

    func rectangle(origin: CGPoint) -> [CGPoint] {
        [
            origin,
            CGPoint(x: origin.x + 100, y: origin.y),
            CGPoint(x: origin.x + 100, y: origin.y + 100),
            CGPoint(x: origin.x, y: origin.y + 100)
        ]
    }
}
#endif
