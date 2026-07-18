// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import PhotoRPG
import SwiftUI
import Testing

@testable import MapRPG

@Suite("Map editor viewport session")
@MainActor
struct MapEditorViewportTransformTests {
    @Test("Measuring the viewport fits the logical map and enables coordinate round trips")
    func measuredViewportFitsLogicalMap() {
        // Given
        let mapSize = CGSize(width: 1_200, height: 800)
        let map = makeMap(name: "Measured map", size: mapSize)
        let sut = makeSession(map: map, containerSize: .zero)

        // When
        sut.updateContainerSize(CGSize(width: 400, height: 300))
        let logicalPoint = CGPoint(x: 735, y: 246)
        let viewportPoint = sut.viewportPoint(fromContent: logicalPoint)

        // Then
        #expect(sut.mapCanvasSize == mapSize)
        #expect(sut.viewport.configuration.id == map.id)
        #expect(sut.viewport.configuration.contentSize == mapSize)
        #expect(sut.viewport.configuration.containerSize == CGSize(width: 400, height: 300))
        #expect(sut.viewport.isAtFit)
        expectApproximately(sut.contentPoint(fromViewport: viewportPoint), logicalPoint)
    }

    @Test("Resizing a zoomed editor preserves the map point under the available center")
    func resizePreservesMapPointAtCenter() {
        // Given
        let map = makeMap(name: "Resizable map", size: CGSize(width: 1_200, height: 800))
        let oldContainerSize = CGSize(width: 400, height: 300)
        let newContainerSize = CGSize(width: 640, height: 300)
        let sut = makeSession(map: map, containerSize: oldContainerSize)
        let oldCenter = CGPoint(x: oldContainerSize.width / 2, y: oldContainerSize.height / 2)
        let zoomed = sut.viewport.geometry.zoomed(
            from: sut.viewport.transform,
            toScale: 0.75,
            anchor: oldCenter
        )
        sut.viewport.commit(zoomed)
        let logicalPoint = sut.contentPoint(fromViewport: oldCenter)

        // When
        sut.updateContainerSize(newContainerSize)
        let newCenter = CGPoint(x: newContainerSize.width / 2, y: newContainerSize.height / 2)

        // Then
        expectApproximately(sut.viewport.transform.scale, zoomed.scale)
        expectApproximately(sut.contentPoint(fromViewport: newCenter), logicalPoint)
    }

    @Test("Switching maps with equal dimensions resets viewport identity and transform")
    func mapSwitchResetsViewportIdentity() {
        // Given
        let size = CGSize(width: 1_200, height: 800)
        let firstMap = makeMap(name: "First map", size: size)
        let secondMap = makeMap(name: "Second map", size: size)
        let sut = makeSession(
            map: firstMap,
            containerSize: CGSize(width: 400, height: 300)
        )
        sut.viewport.commit(
            sut.viewport.geometry.zoomed(
                from: sut.viewport.transform,
                toScale: 1,
                anchor: sut.viewport.geometry.containerCenter
            )
        )
        #expect(!sut.viewport.isAtFit)

        // When
        sut.changeImage(map: secondMap)

        // Then
        #expect(sut.mapId == secondMap.id)
        #expect(sut.viewport.configuration.id == secondMap.id)
        #expect(sut.viewport.isAtFit)
    }

    @Test("Changing logical map bounds atomically refits the viewport")
    func canvasGeometryChangeRefitsViewport() {
        // Given
        let map = makeMap(name: "Bounds map", size: CGSize(width: 1_200, height: 800))
        let sut = makeSession(
            map: map,
            containerSize: CGSize(width: 400, height: 300)
        )
        sut.viewport.commit(
            sut.viewport.geometry.zoomed(
                from: sut.viewport.transform,
                toScale: 1,
                anchor: sut.viewport.geometry.containerCenter
            )
        )
        let newMapSize = CGSize(width: 800, height: 1_600)

        // When
        sut.updateCanvas(image: AKImage(), photoDegrees: 0, mapSize: newMapSize)

        // Then
        #expect(sut.mapCanvasSize == newMapSize)
        #expect(sut.viewport.configuration.contentSize == newMapSize)
        #expect(sut.viewport.isAtFit)
    }

    @Test("Editor first appearance refits while retaining a persisted room focus")
    func editorFirstAppearanceRefitsWhileRetainingFocus() async throws {
        // Given
        let focusedRoom = MapEntryModel(
            id: UUID(),
            name: "Persisted focus",
            content: "",
            coordinates: [
                CGPoint(x: 300, y: 200),
                CGPoint(x: 500, y: 200),
                CGPoint(x: 500, y: 400),
                CGPoint(x: 300, y: 400)
            ],
            focused: true
        )
        let map = MapModel(
            id: UUID(),
            name: "Focused editor map",
            entries: [focusedRoom],
            width: 1_200,
            height: 800
        )
        let sut = makeSession(
            map: map,
            containerSize: CGSize(width: 600, height: 400)
        )
        let zoomed = sut.viewport.geometry.zoomed(
            from: sut.viewport.transform,
            toScale: 1,
            anchor: sut.viewport.geometry.containerCenter
        )
        sut.viewport.commit(zoomed)
        #expect(!sut.viewport.isAtFit)

        // When
        sut.firstAppear(map: map)
        try await Task.sleep(for: .milliseconds(100))
        // macOS can perform a final content-size pass after installing the
        // window toolbar. A fitted editor must remain fitted through it.
        let finalWindowSize = CGSize(width: 620, height: 380)
        sut.updateContainerSize(finalWindowSize)

        // Then
        #expect(sut.viewport.configuration.containerSize == finalWindowSize)
        #expect(sut.viewport.isAtFit)
        expectApproximately(sut.viewport.transform.scale, sut.viewport.geometry.fitScale)
        #expect(sut.focusId == focusedRoom.id)
    }
}

private extension MapEditorViewportTransformTests {
    func makeMap(name: String, size: CGSize) -> MapModel {
        MapModel(
            id: UUID(),
            name: name,
            width: size.width,
            height: size.height
        )
    }

    func makeSession(
        map: MapModel,
        containerSize: CGSize
    ) -> MapEditorSession {
        MapEditorSession(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: containerSize,
            configuration: MapEditorConfiguration(
                mode: .edit,
                displayMode: .master
            )
        )
    }

    func expectApproximately(
        _ actual: CGPoint,
        _ expected: CGPoint,
        tolerance: CGFloat = 0.000_1
    ) {
        expectApproximately(actual.x, expected.x, tolerance: tolerance)
        expectApproximately(actual.y, expected.y, tolerance: tolerance)
    }

    func expectApproximately(
        _ actual: CGFloat,
        _ expected: CGFloat,
        tolerance: CGFloat = 0.000_1
    ) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
#endif
