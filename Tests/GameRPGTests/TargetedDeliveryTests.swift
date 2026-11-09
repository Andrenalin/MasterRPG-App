// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.28 (a targeted message never becomes a broadcast) and §5.29 (a
/// package of a superseded presentation is not sent).
@Suite("Targeted delivery")
@MainActor
struct TargetedDeliveryTests {
    private let reference = GameNetworkModel(
        counter: 7,
        proxyCounter: 0,
        type: .reveal,
        subType: .show,
        gameConfig: .master,
        data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)
    )

    @Test("A message for a player with no route is dropped, not sent to everyone (§5.28)")
    func noRouteIsDropped() async throws {
        let env = try await NetworkStoreTestEnvironment.create()

        await env.networkController.sendPlayer(reference, toPlayer: UUID())

        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
        #expect(env.masterNetworkSpy.calledSendResponseId == 0)
        #expect(env.playerDelegateSpy.calledReceived == 0)
    }

    @Test("The player on the master's own device still gets its message (§5.28)")
    func localPlayerStillReceives() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        env.networkController.model.setLocalPlayers(to: true)

        await env.networkController.sendPlayer(reference, toPlayer: UUID())

        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
        #expect(env.playerDelegateSpy.calledReceived == 1)
    }

    @Test("A message for a routed player goes to its connection (§5.28)")
    func routedPlayerGetsIt() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let connectionId = UUID()
        let playerId = UUID()
        let bound = env.networkController.model.playerRoutes.bind(
            .direct(connectionId),
            to: GameSenderModel(id: playerId, role: .player, name: "", characterId: nil)
        )
        #expect(bound)

        await env.networkController.sendPlayer(reference, toPlayer: playerId)

        #expect(env.masterNetworkSpy.calledSendResponseId == 1)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 0)
    }

    @Test("The package of a presentation that was superseded while it was built is not sent (§5.29)")
    func supersededPackageIsNotSent() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let connectionId = UUID()
        let playerId = UUID()
        _ = env.networkController.model.playerRoutes.bind(
            .direct(connectionId),
            to: GameSenderModel(id: playerId, role: .player, name: "", characterId: nil)
        )
        let payload = NetworkCodableDataType(id: reference.data.id, type: .photo, version: 1, data: Data([1, 2, 3]))

        // Current: the package goes to the connection, then the reference to everyone.
        await env.networkController.sendPresentation(reference, missingPlayers: [playerId]) { payload }
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 1)

        // Superseded: only the reference goes out; the package was built but is not sent.
        var built = false
        await env.networkController.sendPresentation(
            reference,
            missingPlayers: [playerId],
            isSuperseded: { true }
        ) {
            built = true
            return payload
        }
        #expect(built)
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 2)
    }
}
#endif
