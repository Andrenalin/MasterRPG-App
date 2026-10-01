// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import GameRPG
@testable import MapRPG

/// CODE_AUDIT_19 §5.7: while the game master paused "Share Map", battle actions must not
/// broadcast the map state, which carries every room's visibility and all pins.
@MainActor
@Suite("Battle round with paused map sharing")
struct BattleRoundPausedSharingTests {
    @Test("Advancing the turn while sharing is paused sends only the battle round")
    func pausedSharingKeepsMapStatePrivate() async throws {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let spy = PausedSharingNetworkSpy()
        root.networkActions = spy.actions

        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            focused: true
        )
        let map = MapModel(
            id: UUID(),
            name: "Battle map",
            entries: [room],
            mapPins: [
                MapPinModel(id: UUID(), name: "Player", characterId: UUID(), location: CGPoint(x: 20, y: 20), isPlayer: true),
                MapPinModel(id: UUID(), name: "Monster", characterId: UUID(), location: CGPoint(x: 60, y: 60))
            ]
        )
        root.mapRoot.gameController.setGame(item: map, itemId: map.id)
        #expect(root.mapRoot.gameController.startBattle(itemId: map.id, initiativeOrder: .descending))

        root.mapRoot.rootModel.isMapStreaming = false
        #expect(root.battleRoundController.nextRound())

        #expect(!spy.actionsSent.contains(.mapState))
        #expect(spy.actionsSent.contains(.battleRound))

        root.mapRoot.rootModel.isMapStreaming = true
        #expect(root.battleRoundController.nextAttacker())
        #expect(spy.actionsSent.contains(.mapState))
    }

    /// CODE_AUDIT_20 §5.2: the character-sync republish, the replay to a newly ready peer and the
    /// map repair bundle all send content and state through this gate.
    @Test("Map content and state are withheld while sharing is paused, and the map is marked")
    func joinReplayAndRepairHonourPausedSharing() async throws {
        let root = try await MockRoot.createGameRoot()
        let master = MasterController(root: root, asProxy: false)
        let mapId = UUID()

        #expect(master.mayShareMapState(for: mapId))
        #expect(!root.mapRoot.rootModel.mapsWithUnsharedStructure.contains(mapId))

        root.mapRoot.rootModel.isMapStreaming = false

        #expect(!master.mayShareMapState(for: mapId))
        #expect(root.mapRoot.rootModel.mapsWithUnsharedStructure.contains(mapId))
    }
}

@MainActor
private final class PausedSharingNetworkSpy {
    private(set) var actionsSent: [RPGMessageActionType] = []

    lazy var actions = NetworkActions(
        shareId: { _ in },
        send: { _ in },
        game: { [weak self] _, action, _ in
            self?.actionsSent.append(action)
        }
    )
}
