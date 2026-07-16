// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import PhotoRPG
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map tile editing", .serialized)
struct MapEditControllerTileTests {
    @Test("Tile setup uses edit entries as the coordinate source")
    func prepareTileWorkingCopy() throws {
        // Given
        let coordinates = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30, y: 40)
        ]
        let map = makeMap(tileCoordinates: coordinates)
        let editorModel = makeEditorModel(map: map)
        let sut = MapEditController(editController: .preview)

        // When
        sut.prepareTileWorkingCopy(from: map, editorModel: editorModel)

        // Then
        let tileEntry = try #require(editorModel.editEntries.entries.first)
        #expect(editorModel.editEntries.entries.count == 1)
        #expect(tileEntry.id == map.displayConfig.id)
        #expect(tileEntry.coordinates == coordinates)
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == coordinates)
    }

    @Test("Canvas taps only add tile coordinates")
    func canvasTapAddsCoordinate() throws {
        // Given
        let existingCoordinate = CGPoint(x: 10, y: 20)
        let map = makeMap(tileCoordinates: [existingCoordinate])
        let editorModel = makeEditorModel(map: map)
        let sut = MapEditController(editController: .preview)
        sut.prepareTileWorkingCopy(from: map, editorModel: editorModel)
        editorModel.isTapping = .image

        // When
        sut.addTileCoordinateFromCanvas(existingCoordinate, editorModel: editorModel)

        // Then
        let tileEntry = try #require(editorModel.editEntries.entries.first)
        #expect(tileEntry.coordinates == [existingCoordinate, existingCoordinate])
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == tileEntry.coordinates)
        #expect(map.displayConfig.tileCoordinates == [existingCoordinate])
    }

    @Test("Needle interaction consumes its canvas tap without consuming the next tap")
    func needleTapIsConsumed() throws {
        // Given
        let existingCoordinate = CGPoint(x: 10, y: 20)
        let newCoordinate = CGPoint(x: 30, y: 40)
        let map = makeMap(tileCoordinates: [existingCoordinate])
        let editorModel = makeEditorModel(map: map)
        let sut = MapEditController(editController: .preview)
        sut.prepareTileWorkingCopy(from: map, editorModel: editorModel)
        editorModel.isTapping = .image
        editorModel.editEntries.eaten = true

        // When
        sut.addTileCoordinateFromCanvas(newCoordinate, editorModel: editorModel)

        // Then
        #expect(editorModel.editEntries.entries.first?.coordinates == [existingCoordinate])
        #expect(!editorModel.editEntries.eaten)

        // When
        sut.addTileCoordinateFromCanvas(newCoordinate, editorModel: editorModel)

        // Then
        let tileEntry = try #require(editorModel.editEntries.entries.first)
        #expect(tileEntry.coordinates == [existingCoordinate, newCoordinate])
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == tileEntry.coordinates)
    }

    @Test("Needle mutations can synchronize the tile working copy")
    func needleMutationsSynchronizeCoordinates() throws {
        // Given
        let coordinates = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 50, y: 60)
        ]
        let map = makeMap(tileCoordinates: coordinates)
        let editorModel = makeEditorModel(map: map)
        let sut = MapEditController(editController: .preview)
        sut.prepareTileWorkingCopy(from: map, editorModel: editorModel)
        let entryId = try #require(editorModel.editEntries.entries.first?.id)

        // When
        sut.addNeedlePoint(
            at: 0,
            entryId: entryId,
            entries: editorModel.editEntries,
            map: map
        )
        let addedCoordinates = editorModel.editEntries.entry(entryId).coordinates
        sut.syncTileCoordinates(addedCoordinates, editorModel: editorModel)

        // Then
        #expect(addedCoordinates.count == 3)
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == addedCoordinates)

        // When
        sut.removeNeedlePoint(
            at: 1,
            entryId: entryId,
            entries: editorModel.editEntries,
            map: map
        )
        let removedCoordinates = editorModel.editEntries.entry(entryId).coordinates
        sut.syncTileCoordinates(removedCoordinates, editorModel: editorModel)

        // Then
        #expect(removedCoordinates.count == 2)
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == removedCoordinates)
    }

    @Test("Needle drag and accessibility movement synchronize the tile working copy")
    func needleMovementSynchronizesCoordinates() throws {
        // Given
        let start = CGPoint(x: 10, y: 20)
        let dragged = CGPoint(x: 45, y: 70)
        let map = makeMap(tileCoordinates: [start])
        let editorModel = makeEditorModel(map: map)
        let sut = MapEditController(editController: .preview)
        sut.prepareTileWorkingCopy(from: map, editorModel: editorModel)
        let entryId = try #require(editorModel.editEntries.entries.first?.id)
        let needle = NeedleMapPin(
            entries: editorModel.editEntries,
            entryId: entryId,
            index: 0,
            map: map,
            mapEditController: sut,
            coordinatesChanged: { coordinates in
                sut.syncTileCoordinates(coordinates, editorModel: editorModel)
            }
        )

        // When: the drag gesture has updated the shared edit entry and ends.
        editorModel.editEntries.update(coordinate: dragged, for: entryId, at: 0)
        needle.updateCoordinate()

        // Then
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == [dragged])

        // When: an accessibility move action uses the same Needle callback.
        needle.movePointBy(x: 10, y: -5)

        // Then
        let accessibilityMoved = CGPoint(x: 55, y: 65)
        #expect(editorModel.editEntries.entry(entryId).coordinates == [accessibilityMoved])
        #expect(editorModel.workingCopy?.displayConfig.tileCoordinates == [accessibilityMoved])
    }
}

private extension MapEditControllerTileTests {
    func makeMap(tileCoordinates: [CGPoint]) -> MapModel {
        MapModel(
            id: UUID(),
            name: "Tile Test Map",
            displayConfig: DisplayConfigModel(
                id: UUID(),
                tileCoordinates: tileCoordinates,
                border: DisplayBorderViewModel(id: UUID())
            )
        )
    }

    func makeEditorModel(map: MapModel) -> MapEditorModel {
        MapEditorModel(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 600)
        )
    }
}
#endif
