// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// The reconnect (fallback) listener must survive a bad connection. CODE_AUDIT_Join §5.1, §5.3.
@Suite("Player fallback listener — CODE_AUDIT_Join")
@MainActor
struct PlayerFallbackListenerTests {
    /// Reaches the state "connected, then the master was lost, fallback listener up".
    private func makeLostPlayer(
        listener: GameListenerAbstractionMock,
        buildCount: BuildCounter = BuildCounter()
    ) async -> (PlayerNetworkController, PlayerNetworkControllerDelegateSpyingStub) {
        let delegateSpy = PlayerNetworkControllerDelegateSpyingStub()
        let controller = PlayerNetworkController(
            name: "Player",
            delegate: delegateSpy,
            listenerBuilder: { _, _, _, _, _, _ in
                buildCount.value += 1
                return listener
            }
        )
        controller.networkModel.playerConnectionId = UUID()
        controller.networkModel.passcode = "1234"
        let firstId = UUID()
        controller.networkModel.reset(controller: makeConnection(id: firstId, delegate: controller))
        await controller.readyConnection(for: firstId)
        await controller.lostConnection(for: firstId)
        return (controller, delegateSpy)
    }

    @Test("Losing the master starts the fallback listener")
    func lostMasterStartsListener() async {
        let listener = GameListenerAbstractionMock()
        let (controller, delegateSpy) = await makeLostPlayer(listener: listener)

        #expect(controller.networkModel.connectionState == .lost)
        #expect(listener.calledStartListening == 1)
        #expect(delegateSpy.calledLostMaster == 1)
    }

    @Test("A reconnect attempt that fails keeps the player waiting with the listener up (§5.1)")
    func failedAttemptKeepsListener() async {
        let listener = GameListenerAbstractionMock()
        let (controller, _) = await makeLostPlayer(listener: listener)

        await controller.listenerNewConnection(pendingConnection())
        let attemptId = controller.networkModel.connectionController?.id
        #expect(controller.networkModel.connectionState == .notReady)
        await controller.failed(with: "TLS", isAuthenticationFailure: true, for: attemptId ?? UUID())

        #expect(controller.networkModel.connectionState == .lost)
        #expect(controller.networkModel.playerConnectionId != nil)
        #expect(listener.calledStopListening == 0)
        #expect(controller.networkModel.listener != nil)
    }

    @Test("After a failed attempt the next connection is accepted")
    func nextAttemptIsAccepted() async {
        let listener = GameListenerAbstractionMock()
        let (controller, _) = await makeLostPlayer(listener: listener)
        await controller.listenerNewConnection(pendingConnection())
        await controller.failed(with: "TLS", isAuthenticationFailure: true, for: controller.networkModel.connectionController?.id ?? UUID())
        let firstAttempt = controller.networkModel.connectionController?.id

        await controller.listenerNewConnection(pendingConnection())

        #expect(controller.networkModel.connectionState == .notReady)
        #expect(controller.networkModel.connectionController?.id != firstAttempt)
    }

    @Test("A second connection during an attempt is refused and the attempt is left alone")
    func secondConnectionIsRefused() async {
        let listener = GameListenerAbstractionMock()
        let (controller, _) = await makeLostPlayer(listener: listener)
        await controller.listenerNewConnection(pendingConnection())
        let attemptId = controller.networkModel.connectionController?.id

        await controller.listenerNewConnection(pendingConnection())

        #expect(controller.networkModel.connectionController?.id == attemptId)
        #expect(listener.calledStopListening == 0)
    }

    @Test("A reconnect that authenticates retires the listener")
    func successRetiresListener() async {
        let listener = GameListenerAbstractionMock()
        let (controller, delegateSpy) = await makeLostPlayer(listener: listener)
        await controller.listenerNewConnection(pendingConnection())
        let attemptId = controller.networkModel.connectionController?.id ?? UUID()

        await controller.readyConnection(for: attemptId)

        #expect(controller.networkModel.connectionState == .ready)
        #expect(listener.calledStopListening == 1)
        #expect(controller.networkModel.listener == nil)
        #expect(delegateSpy.calledReady == 2)
    }

    @Test("A failed listener is recreated while the player is waiting (§5.3)")
    func failedListenerIsRecreated() async throws {
        let listener = GameListenerAbstractionMock()
        let builds = BuildCounter()
        let (controller, _) = await makeLostPlayer(listener: listener, buildCount: builds)

        await controller.listenerCancelled()

        #expect(controller.networkModel.playerConnectionId != nil)
        #expect(controller.networkModel.listener == nil)
        try await Task.sleep(for: .seconds(1.5))
        #expect(builds.value == 2)
        #expect(controller.networkModel.listener != nil)
        await controller.stop()
    }

    @Test("A failed listener with nothing to wait for stops the controller")
    func failedListenerWithoutSessionStops() async {
        let controller = PlayerNetworkController(name: "Player", delegate: PlayerNetworkControllerDelegateSpyingStub())
        controller.networkModel.playerConnectionId = UUID()

        await controller.listenerCancelled()

        #expect(controller.networkModel.playerConnectionId == nil)
    }

    @Test("A rejected initial join records why it failed (§8.2)")
    func joinFailureReasonIsRecorded() async {
        for (isAuthentication, expected) in [(true, PlayerJoinFailure.badCode), (false, .unreachable)] {
            let controller = PlayerNetworkController(name: "Player", delegate: PlayerNetworkControllerDelegateSpyingStub())
            controller.networkModel.playerConnectionId = UUID()
            let id = UUID()
            controller.networkModel.reset(controller: makeConnection(id: id, delegate: controller))

            await controller.failed(with: "handshake", isAuthenticationFailure: isAuthentication, for: id)

            #expect(controller.networkModel.joinFailure == expected)
            #expect(controller.networkModel.playerConnectionId == nil)
        }
    }

    @Test("Stopping clears the join code and session")
    func stopClearsSecrets() async {
        let controller = PlayerNetworkController(name: "Player", delegate: PlayerNetworkControllerDelegateSpyingStub())
        controller.networkModel.passcode = "1234"
        controller.networkModel.sessionId = "session"

        await controller.stop()

        #expect(controller.networkModel.passcode.isEmpty)
        #expect(controller.networkModel.sessionId == nil)
    }

    /// An unroutable address keeps the connection pending instead of failing on its own.
    private func pendingConnection() -> NWConnection {
        NWConnection(host: NWEndpoint.Host("192.0.2.1"), port: 9, using: .tcp)
    }

    private func makeConnection(id: ConnectionController.ID, delegate: any ConnectionControllerDelegate) -> ConnectionController {
        ConnectionController(id: id, connection: pendingConnection(), delegate: delegate)
    }
}

@MainActor
final class BuildCounter {
    var value = 0
}
#endif
