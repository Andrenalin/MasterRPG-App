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

    @Test("A retained editor fits a replacement map using its new canvas geometry")
    func replacementMapUsesNewCanvasBeforeCompletingFit() {
        let firstMap = makeMap(
            name: "Landscape",
            size: CGSize(width: 1_200, height: 800)
        )
        let secondMap = makeMap(
            name: "Portrait",
            size: CGSize(width: 500, height: 1_500)
        )
        let windowSize = CGSize(width: 600, height: 400)
        let sut = makeSession(map: firstMap, containerSize: windowSize)
        sut.firstAppear(map: firstMap)
        sut.viewport.commit(
            sut.viewport.geometry.zoomed(
                from: sut.viewport.transform,
                toScale: 1,
                anchor: sut.viewport.geometry.containerCenter
            )
        )
        #expect(!sut.viewport.isAtFit)

        sut.changeImage(map: secondMap)
        sut.updateCanvas(map: secondMap, image: AKImage(), photoDegrees: 0)
        sut.firstAppear(map: secondMap)

        #expect(sut.mapId == secondMap.id)
        #expect(sut.viewport.configuration.id == secondMap.id)
        #expect(sut.viewport.configuration.contentSize == CGSize(width: 500, height: 1_500))
        #expect(sut.viewport.configuration.containerSize == windowSize)
        #expect(sut.viewport.isAtFit)
        expectApproximately(sut.viewport.transform.scale, 400 / 1_500)
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
        let resizedMap = MapModel(
            id: map.id,
            name: map.name,
            width: newMapSize.width,
            height: newMapSize.height
        )

        // When
        sut.updateCanvas(map: resizedMap, image: AKImage(), photoDegrees: 0)

        // Then
        #expect(sut.mapCanvasSize == newMapSize)
        #expect(sut.viewport.configuration.contentSize == newMapSize)
        #expect(sut.viewport.isAtFit)
    }

    @Test("Editor first appearance refits while retaining a persisted room focus")
    func editorFirstAppearanceRefitsWhileRetainingFocus() {
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

    @Test("Game map waits for valid geometry, then initially fits instead of applying persisted focus")
    func gameInitialFitWaitsForGeometry() {
        let focusedRoom = MapEntryModel(
            id: UUID(),
            name: "Persisted game focus",
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
            name: "Game map",
            entries: [focusedRoom],
            width: 1_200,
            height: 800
        )
        let sut = makeSession(map: map, containerSize: .zero, mode: .gameMaster)

        sut.firstAppear(map: map)
        sut.updateContainerSize(CGSize(width: 600, height: 400))

        #expect(sut.focusId == focusedRoom.id)
        #expect(sut.viewport.configuration.id == map.id)
        #expect(sut.viewport.isAtFit)
    }

    @Test("Late initial room hydration seeds persisted focus without changing fit")
    func lateInitialRoomHydrationPreservesFit() {
        let map = makeMap(
            name: "Late room hydration",
            size: CGSize(width: 1_200, height: 800)
        )
        let sut = makeSession(
            map: map,
            containerSize: CGSize(width: 600, height: 400),
            mode: .gameMaster
        )
        sut.firstAppear(map: map)
        let fittedTransform = sut.viewport.transform
        let focusedRoom = MapEntryModel(
            id: UUID(),
            name: "Persisted room",
            content: "",
            coordinates: [
                CGPoint(x: 700, y: 400),
                CGPoint(x: 850, y: 400),
                CGPoint(x: 850, y: 550),
                CGPoint(x: 700, y: 550)
            ],
            focused: true
        )
        let hydratedMap = MapModel(
            id: map.id,
            name: map.name,
            entries: [focusedRoom],
            width: map.width,
            height: map.height
        )

        sut.resetEntries(newEntries: hydratedMap.entries, map: hydratedMap)

        #expect(sut.focusId == focusedRoom.id)
        #expect(sut.viewport.isAtFit)
        #expect(sut.viewport.transform == fittedTransform)
    }

    @Test("Focus-only changes after late hydration retain game room focusing")
    func focusOnlyChangeAfterLateHydrationFocusesRoom() throws {
        let map = makeMap(
            name: "Late focus update",
            size: CGSize(width: 1_200, height: 800)
        )
        let sut = makeSession(
            map: map,
            containerSize: CGSize(width: 600, height: 400),
            mode: .gameMaster
        )
        sut.firstAppear(map: map)
        var firstRoom = MapEntryModel(
            id: UUID(),
            name: "First room",
            content: "",
            coordinates: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 250, y: 100),
                CGPoint(x: 250, y: 250),
                CGPoint(x: 100, y: 250)
            ],
            focused: true
        )
        var secondRoom = MapEntryModel(
            id: UUID(),
            name: "Second room",
            content: "",
            coordinates: [
                CGPoint(x: 750, y: 450),
                CGPoint(x: 900, y: 450),
                CGPoint(x: 900, y: 600),
                CGPoint(x: 750, y: 600)
            ]
        )
        let hydratedMap = MapModel(
            id: map.id,
            name: map.name,
            entries: [firstRoom, secondRoom],
            width: map.width,
            height: map.height
        )
        sut.resetEntries(newEntries: hydratedMap.entries, map: hydratedMap)
        #expect(sut.viewport.isAtFit)

        firstRoom.focused = false
        secondRoom.focused = true
        let focusUpdate = MapModel(
            id: map.id,
            name: map.name,
            entries: [firstRoom, secondRoom],
            width: map.width,
            height: map.height
        )

        sut.resetEntries(newEntries: focusUpdate.entries, map: focusUpdate)

        let focusedNode = try #require(sut.entries.roomNode(for: secondRoom.id))
        #expect(sut.focusId == secondRoom.id)
        #expect(!sut.viewport.isAtFit)
        expectApproximately(
            sut.contentPoint(fromViewport: sut.viewport.geometry.containerCenter),
            CGPoint(x: focusedNode.bounds.midX, y: focusedNode.bounds.midY)
        )
    }

    @Test("First appearance remains hidden until a valid window measurement completes the fit")
    func firstAppearanceWaitsForValidWindowMeasurement() {
        // Given
        let map = makeMap(name: "Deferred window map", size: CGSize(width: 1_200, height: 800))
        let sut = makeSession(map: map, containerSize: .zero)

        // When
        sut.firstAppear(map: map)

        // Then
        #expect(!sut.appeared)
        #expect(sut.viewport.configuration.containerSize == .zero)

        // When
        let windowSize = CGSize(width: 600, height: 400)
        sut.updateContainerSize(windowSize)

        // Then
        #expect(sut.appeared)
        #expect(sut.viewport.configuration.containerSize == windowSize)
        #expect(sut.viewport.isAtFit)
        expectApproximately(sut.viewport.transform.scale, 0.5)
    }

    @Test("Changing the active editor room preserves the viewport")
    func changingActiveRoomPreservesViewport() throws {
        // Given
        let initialRoom = MapEntryModel(
            id: UUID(),
            name: "Initial room",
            content: "",
            coordinates: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
                CGPoint(x: 100, y: 300)
            ]
        )
        let nextRoom = MapEntryModel(
            id: UUID(),
            name: "Next room",
            content: "",
            coordinates: [
                CGPoint(x: 500, y: 300),
                CGPoint(x: 700, y: 300),
                CGPoint(x: 700, y: 500),
                CGPoint(x: 500, y: 500)
            ]
        )
        let map = MapModel(
            id: UUID(),
            name: "Room navigation map",
            entries: [initialRoom, nextRoom],
            width: 1_200,
            height: 800
        )
        let editorModel = makeSession(
            map: map,
            containerSize: CGSize(width: 600, height: 400)
        )
        let sut = MapEditController(editController: .preview)
        sut.prepareWorkingCopy(from: map, editorModel: editorModel)

        // When: the persisted/editor selection is installed before the window appears.
        sut.changeMap(
            map: map,
            currentEntryId: initialRoom.id,
            editorModel: editorModel
        )
        editorModel.firstAppear(map: map)

        // Then: initial presentation always shows the complete map.
        #expect(editorModel.appeared)
        #expect(editorModel.viewport.isAtFit)
        #expect(editorModel.editEntries.entries.first?.id == initialRoom.id)

        // Given: the user has established a manual viewport before moving to
        // the next room in the editor.
        let manualViewport = editorModel.viewport.geometry.interacting(
            from: editorModel.viewport.transform,
            translation: CGSize(width: -75, height: 40),
            magnification: 1.6,
            anchor: editorModel.viewport.geometry.containerCenter
        )
        editorModel.viewport.commit(manualViewport)
        let viewportBeforeSelection = editorModel.viewport.transform

        // When: the user moves to the next room after presentation.
        sut.changeMap(
            map: map,
            currentEntryId: nextRoom.id,
            editorModel: editorModel
        )

        // Then: only the active room/needles change. Room navigation must not
        // pan, zoom, or otherwise rewrite the user's viewport.
        let activeRoom = try #require(editorModel.editEntries.entries.first)
        #expect(editorModel.editEntries.entries.first?.id == nextRoom.id)
        #expect(activeRoom.coordinates == nextRoom.coordinates)
        #expect(editorModel.viewport.transform == viewportBeforeSelection)
    }

    @Test("A room selection made while window geometry is pending still finishes at full-map fit")
    func deferredRoomSelectionPreservesInitialFit() throws {
        let initialRoom = MapEntryModel(
            id: UUID(),
            name: "Initial room",
            content: "",
            coordinates: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
                CGPoint(x: 100, y: 300)
            ]
        )
        let selectedRoom = MapEntryModel(
            id: UUID(),
            name: "Deferred selection",
            content: "",
            coordinates: [
                CGPoint(x: 700, y: 400),
                CGPoint(x: 850, y: 400),
                CGPoint(x: 850, y: 550),
                CGPoint(x: 700, y: 550)
            ]
        )
        let map = MapModel(
            id: UUID(),
            name: "Deferred room map",
            entries: [initialRoom, selectedRoom],
            width: 1_200,
            height: 800
        )
        let editorModel = makeSession(map: map, containerSize: .zero)
        let sut = MapEditController(editController: .preview)
        sut.prepareWorkingCopy(from: map, editorModel: editorModel)
        sut.changeMap(
            map: map,
            currentEntryId: initialRoom.id,
            editorModel: editorModel
        )
        editorModel.firstAppear(map: map)

        sut.changeMap(
            map: map,
            currentEntryId: selectedRoom.id,
            editorModel: editorModel
        )
        editorModel.updateContainerSize(CGSize(width: 600, height: 400))

        #expect(editorModel.appeared)
        #expect(editorModel.editEntries.entries.first?.id == selectedRoom.id)
        #expect(editorModel.viewport.isAtFit)
        expectApproximately(
            editorModel.viewport.transform.scale,
            editorModel.viewport.geometry.fitScale
        )
    }

    @Test("A logical-canvas pinch anchor converts into viewport coordinates")
    func logicalCanvasPinchAnchorUsesViewportSpace() {
        let mapSize = CGSize(width: 1_200, height: 800)
        let map = makeMap(name: "Pinch anchor", size: mapSize)
        let sut = makeSession(
            map: map,
            containerSize: CGSize(width: 600, height: 400)
        )

        let anchor = MapViewportGestureSurface.content(mapSize).viewportAnchor(
            forStartLocation: CGPoint(x: 900, y: 200),
            session: sut
        )

        expectApproximately(anchor, CGPoint(x: 450, y: 100))
    }

    @Test("A transient zero measurement does not destroy a manually zoomed viewport")
    func zeroMeasurementIsIgnored() {
        let map = makeMap(name: "Stable map", size: CGSize(width: 1_200, height: 800))
        let containerSize = CGSize(width: 600, height: 400)
        let sut = makeSession(map: map, containerSize: containerSize)
        sut.firstAppear(map: map)
        sut.viewport.commit(
            sut.viewport.geometry.zoomed(
                from: sut.viewport.transform,
                toScale: 1,
                anchor: sut.viewport.geometry.containerCenter
            )
        )
        let zoomed = sut.viewport.transform

        sut.updateContainerSize(.zero)

        #expect(sut.viewport.configuration.containerSize == containerSize)
        #expect(sut.viewport.transform == zoomed)
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
        containerSize: CGSize,
        mode: MapMode = .edit
    ) -> MapEditorSession {
        MapEditorSession(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: containerSize,
            configuration: MapEditorConfiguration(
                mode: mode,
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
