// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
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

    @Test("Show all rooms renders and broadcasts as one transaction")
    func showAllRoomsBroadcastsOnce() async throws {
        let rooms = ["Hall", "Kitchen", "Vault"].map {
            MapEntryModel(
                id: UUID(),
                name: $0,
                content: "",
                coordinates: Self.square,
                isShown: false
            )
        }
        let fixture = try await makeFixture(entries: rooms, isGameMaster: true)

        await fixture.game.setAllRoomsShown(true)

        #expect(fixture.liveMap.entries.allSatisfy { $0.isShown })
        #expect(fixture.networkSpy.calls.count == 1)
        #expect(fixture.networkSpy.calls.first?.action == .mapState)
    }

    @Test("Pointer controls work without a 2D editor and broadcast once per command")
    func pointerControlsAreAutonomous() async throws {
        let fixture = try await makeFixture(entries: [], isGameMaster: true)
        fixture.liveMap.pointer.location = .zero
        fixture.liveMap.pointer.isShown = false

        fixture.game.movePointerToMapCenter()

        #expect(fixture.liveMap.pointer.location == CGPoint(x: 600, y: 400))
        #expect(fixture.liveMap.pointer.isShown)
        #expect(fixture.networkSpy.calls.count == 1)
        #expect(fixture.networkSpy.calls.first?.action == .mapState)

        fixture.game.togglePointerVisibility()

        #expect(!fixture.liveMap.pointer.isShown)
        #expect(fixture.networkSpy.calls.count == 2)
        #expect(fixture.networkSpy.calls.allSatisfy { $0.action == .mapState })
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
