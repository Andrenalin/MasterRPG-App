// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import RealityKit
import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Standalone tabletop controls")
struct GameTableControlTests {
    @Test("Game master toggles one room and broadcasts one map state")
    func gameMasterTogglesRoomOnce() async throws {
        let room = MapEntryModel(
            id: UUID(),
            name: "Library",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let fixture = try await makeFixture(entries: [room], isGameMaster: true)

        await fixture.game.toggleRoomVisibility(room.id)

        #expect(fixture.liveMap.entries.first?.isShown == true)
        #expect(fixture.networkSpy.calls.count == 1)
        #expect(fixture.networkSpy.calls.first?.action == .mapState)
        #expect(fixture.networkSpy.calls.first?.data.id == fixture.liveMap.id)
    }

    @Test("Paused sharing keeps game-master edits local; an explicit reshare still sends")
    func pausedSharingKeepsEditsLocal() async throws {
        let room = MapEntryModel(
            id: UUID(),
            name: "Secret",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let fixture = try await makeFixture(entries: [room], isGameMaster: true)
        fixture.game.isStreaming = false

        await fixture.game.toggleRoomVisibility(room.id)
        await fixture.game.toggleRoomFocus(room.id)

        #expect(fixture.liveMap.entries.first?.isShown == true)
        #expect(fixture.networkSpy.calls.isEmpty)

        fixture.game.sendMapUpdates()

        #expect(fixture.networkSpy.calls.count == 1)
        #expect(fixture.networkSpy.calls.first?.action == .mapState)
    }

    @Test("Only the game master gets room hit volumes")
    func roomHitVolumesAreGameMasterOnly() async throws {
        let room = MapEntryModel(
            id: UUID(),
            name: "Hall",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let master = try await makeFixture(entries: [room], isGameMaster: true)
        master.game.syncPawnsWithMapPins()
        #expect(master.game.setup.roomHitAreas.map(\.roomId) == [room.id])

        let player = try await makeFixture(entries: [room], isGameMaster: false)
        player.game.syncPawnsWithMapPins()
        #expect(player.game.setup.roomHitAreas.isEmpty)
    }

    @Test("A drop that is not applied snaps the token back to the model's location")
    func rejectedDropSnapsPawnBack() async throws {
        let playerId = UUID()
        let fixture = try await makeFixture(entries: [], isGameMaster: false)
        fixture.game.playerPinId = playerId
        fixture.liveMap.mapPins = [MapPinModel(id: playerId, name: "Player", isPlayer: true)]
        fixture.game.syncPawnsWithMapPins()
        let pawn = try #require(fixture.game.setup.pinPawns.first { $0.pinId == playerId })
        let home = pawn.entity.position

        // The fixture has no map image, so the drop cannot be applied.
        fixture.game.pinDragChanged(pinId: playerId, position: SIMD3<Float>(0.3, 0, 0.3))
        #expect(pawn.entity.position != home)
        fixture.game.pinDragEnded(pinId: playerId, position: SIMD3<Float>(0.3, 0, 0.3))

        #expect(pawn.entity.position == home)
        #expect(fixture.networkSpy.calls.isEmpty)
    }

    @Test("Player cannot change room visibility")
    func playerCannotToggleRoom() async throws {
        let room = MapEntryModel(
            id: UUID(),
            name: "Vault",
            content: "",
            coordinates: Self.square,
            isShown: false
        )
        let fixture = try await makeFixture(entries: [room], isGameMaster: false)

        await fixture.game.toggleRoomVisibility(room.id)

        #expect(fixture.liveMap.entries.first?.isShown == false)
        #expect(fixture.networkSpy.calls.isEmpty)
    }

    /// CODE_AUDIT_19 §9.11: the toolbar's "point" action on the 2D map and the 3D table uses this
    /// one routine; the tests used to exercise 3D-only copies the UI never ran.
    @Test("Pointing moves the pointer to the map centre and shows it")
    func showPointerAtMapCenter() async throws {
        let fixture = try await makeFixture(entries: [], isGameMaster: true)
        fixture.liveMap.pointer.location = .zero
        fixture.liveMap.pointer.isShown = false
        let controller = fixture.game.mapRoot.mapGameControllable

        #expect(controller.showPointerAtMapCenter(itemId: fixture.liveMap.id))

        #expect(fixture.liveMap.pointer.location == CGPoint(x: 600, y: 400))
        #expect(fixture.liveMap.pointer.isShown)
        #expect(!controller.showPointerAtMapCenter(itemId: fixture.liveMap.id))
    }

    @Test("Players can move only their own token and a visible shared pointer")
    func playerMovementPermissionsMatchThe2DGameMap() async throws {
        let playerId = UUID()
        let otherId = UUID()
        let fixture = try await makeFixture(entries: [], isGameMaster: false)
        fixture.game.playerPinId = playerId
        fixture.liveMap.mapPins = [
            MapPinModel(id: playerId, name: "Player", isPlayer: true),
            MapPinModel(id: otherId, name: "Other")
        ]

        fixture.liveMap.pointer.isShown = false
        #expect(fixture.game.canMovePin(playerId))
        #expect(!fixture.game.canMovePin(otherId))
        #expect(!fixture.game.canMovePin(fixture.liveMap.pointer.id))

        fixture.liveMap.pointer.isShown = true
        #expect(fixture.game.canMovePin(fixture.liveMap.pointer.id))
    }

    /// CODE_AUDIT_19 §5.17: each 2D↔3D toggle builds a new table model; the GM's preview lens
    /// lives on the map root, so the next model starts from it instead of `.master`.
    @Test("The game master's display mode outlives the table model")
    func displayModeOutlivesTableModel() async throws {
        let fixture = try await makeFixture(entries: [], isGameMaster: true)
        fixture.game.displayMode = .player

        #expect(fixture.game.mapRoot.rootModel.gameDisplayMode == .player)

        let nextModel = GameTableModel(mapRoot: fixture.game.mapRoot, photoRoot: fixture.game.photoRoot)
        nextModel.isGameMaster = true
        nextModel.displayMode = fixture.game.mapRoot.rootModel.gameDisplayMode
        #expect(nextModel.displayMode == .player)
    }

    /// CODE_AUDIT_28 §5.15: the lens re-rendered the fog but left the hidden pins on the table.
    @Test("Previewing as a player removes the hidden pin tokens at once")
    func playerLensRemovesHiddenPins() async throws {
        let fixture = try await makeFixture(entries: [], isGameMaster: true)
        let hiddenId = UUID()
        fixture.liveMap.mapPins = [MapPinModel(id: hiddenId, name: "Ambush", isShown: false)]
        fixture.game.syncPawnsWithMapPins()
        #expect(fixture.game.setup.pinPawns.contains { $0.pinId == hiddenId })

        fixture.game.displayMode = .player
        #expect(!fixture.game.setup.pinPawns.contains { $0.pinId == hiddenId })

        fixture.game.displayMode = .master
        #expect(fixture.game.setup.pinPawns.contains { $0.pinId == hiddenId })
    }

    /// CODE_AUDIT_19 §5.17: the reshare baseline starts at the map's values, not the defaults.
    @Test("Resetting the reshare baseline leaves nothing to reshare")
    func resetReshareMatchesCurrentMap() async throws {
        let fixture = try await makeFixture(entries: [], isGameMaster: true)
        fixture.liveMap.pinScale = 2

        #expect(fixture.game.canReshare)
        fixture.game.resetReshare()
        #expect(!fixture.game.canReshare)
    }

    private func makeFixture(
        entries: [MapEntryModel],
        isGameMaster: Bool
    ) async throws -> GameTableControlFixture {
        let persistentMap = MapModel(
            id: MapModel.previewId,
            name: "Table test map",
            entries: entries
        )
        let mapRoot = MapRootModel.previewFixture(models: [persistentMap])
        let liveMap = try #require(
            mapRoot.mapGameControllable.gameModel.itemData[persistentMap.id] as? MapModel
        )
        let game = GameTableModel(mapRoot: mapRoot, photoRoot: mapRoot.photoRoot)
        let networkSpy = GameTableControlNetworkSpy()
        game.currentMapId = persistentMap.id
        game.isGameMaster = isGameMaster
        game.networkActions = networkSpy.actions

        return GameTableControlFixture(
            game: game,
            liveMap: liveMap,
            networkSpy: networkSpy
        )
    }

    private static let square = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100)
    ]
}

private struct GameTableControlFixture {
    let game: GameTableModel
    let liveMap: MapModel
    let networkSpy: GameTableControlNetworkSpy
}

@MainActor
private final class GameTableControlNetworkSpy {
    struct Call {
        let data: NetworkCodableDataType
        let action: RPGMessageActionType
    }

    private(set) var calls: [Call] = []

    lazy var actions = NetworkActions(
        shareId: { _ in },
        send: { _ in },
        game: { [weak self] data, action, _ in
            self?.calls.append(Call(data: data, action: action))
        }
    )
}

#endif
