// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor game message flow")
struct MapEditorGameMessageFlowTests {
    @Test("Game-master room visibility sends one authoritative map state")
    func roomVisibilitySendsOneAuthoritativeMapState() throws {
        // Given
        let room = MapEntryModel(
            id: UUID(),
            name: "Library",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let fixture = makeFixture(entries: [room])
        let entriesRevisionBeforeToggle = fixture.liveMap.entries_.update

        // The presentation flag controls whether the map surface is currently
        // shared. It must not suppress authoritative game-state mutations.
        fixture.session.isStreaming = false

        // When
        fixture.session.route(.toggleRoomVisibility(room.id))

        // Then
        #expect(fixture.liveMap.entries.first?.isShown == true)
        #expect(fixture.session.entries.entry(room.id).isShown == true)
        #expect(fixture.liveMap.entries_.update != entriesRevisionBeforeToggle)
        #expect(fixture.updateSpy.updates.count == 1)

        let update = try #require(fixture.updateSpy.updates.first)
        #expect(update.id == fixture.liveMap.id)
        #expect(update.type == .map)
        #expect(update.version == fixture.liveMap.version)
        #expect(
            update.contentVersion
                == fixture.root.gameController.mapContentVersion(for: fixture.liveMap.id)
        )

        let state = try #require(update.data.flatMap { String(data: $0, encoding: .utf8) })
        #expect(state.hasPrefix("\(room.id):true:false|"))
    }

    @Test("Game-master room focus sends one authoritative map state")
    func roomFocusSendsOneAuthoritativeMapState() throws {
        // Given
        let room = MapEntryModel(
            id: UUID(),
            name: "Vault",
            content: "",
            coordinates: Self.square,
            isShown: true,
            focused: false
        )
        let fixture = makeFixture(entries: [room])
        let entriesRevisionBeforeToggle = fixture.liveMap.entries_.update

        // When
        fixture.session.route(.toggleRoomFocus(room.id))

        // Then
        #expect(fixture.liveMap.entries.first?.focused == true)
        #expect(fixture.session.entries.entry(room.id).focused == true)
        #expect(fixture.liveMap.entries_.update != entriesRevisionBeforeToggle)
        #expect(fixture.updateSpy.updates.count == 1)

        let update = try #require(fixture.updateSpy.updates.first)
        let state = try #require(update.data.flatMap { String(data: $0, encoding: .utf8) })
        #expect(state.hasPrefix("\(room.id):true:true|"))
    }

    @Test("Game-master room focus ignores a stale view map")
    func roomFocusMutatesAuthoritativeLiveMap() throws {
        // Given: retained views can briefly hold a different MapModel instance
        // with the same id as the game controller's authoritative live item.
        let room = MapEntryModel(
            id: UUID(),
            name: "Observatory",
            content: "",
            coordinates: Self.square,
            isShown: true,
            focused: false
        )
        let fixture = makeFixture(entries: [room], routerUsesLiveMap: false)

        // When
        fixture.session.route(.toggleRoomFocus(room.id))

        // Then
        #expect(fixture.liveMap.entries.first?.focused == true)
        #expect(fixture.routerMap.entries.first?.focused == false)
        #expect(fixture.session.focusId == room.id)
        #expect(fixture.updateSpy.updates.count == 1)
        let update = try #require(fixture.updateSpy.updates.first)
        let state = try #require(update.data.flatMap { String(data: $0, encoding: .utf8) })
        #expect(state.hasPrefix("\(room.id):true:true|"))
    }

    @Test("Player cannot toggle authoritative room visibility")
    func playerCannotToggleRoomVisibility() {
        // Given
        let room = MapEntryModel(
            id: UUID(),
            name: "Secret room",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let fixture = makeFixture(entries: [room], mode: .player)

        // When
        fixture.session.route(.toggleRoomVisibility(room.id))

        // Then
        #expect(fixture.liveMap.entries.first?.isShown == false)
        #expect(fixture.session.entries.entry(room.id).isShown == false)
        #expect(fixture.updateSpy.updates.isEmpty)
    }

    @Test("Player cannot initiate authoritative room focus")
    func playerCannotToggleRoomFocus() {
        // Given
        let room = MapEntryModel(
            id: UUID(),
            name: "Master focus only",
            content: "",
            coordinates: Self.square,
            isShown: true,
            focused: false
        )
        let fixture = makeFixture(entries: [room], mode: .player)
        let viewportBeforeAttempt = fixture.session.viewport.transform

        // When: exercise the router directly as a defense-in-depth check;
        // player room hit targets are also disabled in the view layer.
        fixture.session.route(.toggleRoomFocus(room.id))

        // Then
        #expect(fixture.liveMap.entries.first?.focused == false)
        #expect(fixture.session.entries.entry(room.id).focused == false)
        #expect(fixture.session.focusId == nil)
        #expect(fixture.session.viewport.transform == viewportBeforeAttempt)
        #expect(fixture.updateSpy.updates.isEmpty)
    }

    @Test("Pointing mode shows and positions the pointer in one canvas action")
    func pointingModeShowsPointerImmediately() {
        let fixture = makeFixture(entries: [])
        let viewportLocation = CGPoint(x: 320, y: 240)
        let expectedLocation = fixture.session.contentPoint(fromViewport: viewportLocation)
        fixture.session.isPointing = true

        fixture.session.route(.canvasTap(viewportLocation))

        #expect(fixture.session.isPointerInteractionActive)
        #expect(fixture.liveMap.pointer.isShown)
        #expect(fixture.liveMap.pointer.location == expectedLocation)
        #expect(fixture.session.pins.pointer == fixture.liveMap.pointer)
        #expect(fixture.updateSpy.updates.count == 1)
    }

    @Test("Hex toggle mutates the session map and reveals reshare")
    func hexToggleUsesTheAuthoritativeSessionMap() {
        let fixture = makeFixture(entries: [], routerUsesLiveMap: false)

        fixture.session.route(.toggleHexGrid)

        #expect(fixture.liveMap.entries.contains(where: { $0.isHexGrid }))
        #expect(!fixture.routerMap.entries.contains(where: { $0.isHexGrid }))
        #expect(fixture.session.isHexMap)
        #expect(fixture.session.canReshare)

        fixture.session.resetReshare()
        #expect(!fixture.session.canReshare)

        fixture.session.route(.toggleHexGrid)
        #expect(!fixture.liveMap.entries.contains(where: { $0.isHexGrid }))
        #expect(!fixture.session.isHexMap)
        #expect(fixture.session.canReshare)
    }

    private func makeFixture(
        entries: [MapEntryModel],
        mode: MapMode = .gameMaster,
        routerUsesLiveMap: Bool = true
    ) -> MapEditorGameMessageFixture {
        let persistentMap = MapModel(
            id: MapModel.previewId,
            name: "Game message test map",
            entries: entries
        )
        let root = MapRootModel.previewFixture(models: [persistentMap])
        let liveMap = root.gameController.gameItem(for: persistentMap.id)
        let routerMap = routerUsesLiveMap ? liveMap : persistentMap
        let updateSpy = MapStateUpdateSpy()
        let actions = MapEditorActions(
            sendMapUpdates: {
                updateSpy.record(
                    root.gameController.networkMapUpdate(for: liveMap.id)
                )
            },
            focused: {
                updateSpy.record(
                    root.gameController.networkMapUpdate(for: liveMap.id)
                )
            }
        )
        let session = MapEditorSession(
            map: liveMap,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            configuration: MapEditorConfiguration(
                mode: mode,
                displayMode: mode == .player ? .player : .master
            ),
            actions: actions
        )
        session.installActionRouter(
            MapEditorActionRouter(
                session: session,
                editController: root.editController,
                mapEditController: MapEditController(editController: root.editController),
                map: routerMap,
                root: root
            )
        )

        return MapEditorGameMessageFixture(
            root: root,
            liveMap: liveMap,
            routerMap: routerMap,
            session: session,
            updateSpy: updateSpy
        )
    }

    private static let square = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100),
    ]
}

@MainActor
private struct MapEditorGameMessageFixture {
    let root: MapRootModel
    let liveMap: MapModel
    let routerMap: MapModel
    let session: MapEditorSession
    let updateSpy: MapStateUpdateSpy
}

@MainActor
private final class MapStateUpdateSpy {
    private(set) var updates: [NetworkCodableDataType] = []

    func record(_ update: NetworkCodableDataType) {
        updates.append(update)
    }
}

#endif
