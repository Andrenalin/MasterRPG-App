// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import os.log
import CoreRPG
import Testing

@testable import GameRPG

/// The real master and player controllers over real Bonjour + TLS-PSK on loopback.
@Suite("End-to-end LAN join")
@MainActor
struct EndToEndJoinTests {
    private func makeHost(code: String, delegate: MasterNetworkControllerDelegateMock = MasterNetworkControllerDelegateMock()) async throws -> (MasterNetworkController, BrowserGameModel) {
        let name = "JoinTest-\(UUID().uuidString.prefix(8))"
        let master = MasterNetworkController(
            name: name,
            delegate: delegate,
            listenerBuilder: MasterNetworkController.gameListenerBuilder(),
            hostingSessions: HostingSessionStore(storage: InMemoryJoinCodeStorage())
        )
        master.startStreaming(passcode: code)
        try await Task.sleep(for: .seconds(2))
        let game = BrowserGameModel(id: UUID(), endpointName: name, connectionMode: .observer, sessionId: master.networkModel.sessionId)
        return (master, game)
    }

    @Test("Joining with the host's code succeeds")
    func joinWithRightCode() async throws {
        let (master, game) = try await makeHost(code: "4821")
        defer { master.stopStreaming() }
        let player = PlayerNetworkController(name: "Player", delegate: PlayerNetworkControllerDelegateSpyingStub())

        let joined = await player.toggleConnection(to: game, passcode: "4821")
        await player.stop()

        #expect(joined, "failure: \(String(describing: player.networkModel.joinFailure))")
    }

    @Test("A player reconnects when the master ends and restarts the game, and messages flow both ways")
    func playerReconnectsAfterMasterRestart() async throws {
        let masterDelegate = MasterNetworkControllerDelegateMock()
        let (master, game) = try await makeHost(code: "4821", delegate: masterDelegate)
        defer { master.stopStreaming() }
        let playerDelegate = PlayerNetworkControllerDelegateSpyingStub()
        let player = PlayerNetworkController(name: "Player-\(UUID().uuidString.prefix(8))", delegate: playerDelegate)
        defer { Task { await player.stop() } }
        #expect(await player.toggleConnection(to: game, passcode: "4821"))
        #expect(await exchangesMessages(master: master, masterDelegate: masterDelegate, player: player, playerDelegate: playerDelegate), "before the restart")

        master.stopStreaming()
        let lost = await waitFor(.lost, of: player, timeout: .seconds(15))
        master.startStreaming(passcode: "4821")
        let reconnected = await waitFor(.ready, of: player, timeout: .seconds(20))

        #expect(lost, "the player notices the master is gone")
        #expect(reconnected, "the restarted master redials the waiting player: \(player.networkModel.connectionState)")
        #expect(await exchangesMessages(master: master, masterDelegate: masterDelegate, player: player, playerDelegate: playerDelegate), "after the restart")
    }

    /// Sends one message each way over the current connections and waits for both to arrive.
    private func exchangesMessages(
        master: MasterNetworkController,
        masterDelegate: MasterNetworkControllerDelegateMock,
        player: PlayerNetworkController,
        playerDelegate: PlayerNetworkControllerDelegateSpyingStub
    ) async -> Bool {
        let masterReceived = masterDelegate.calledReceived
        let playerReceived = playerDelegate.calledReceived
        for connection in master.networkModel.connections {
            await connection.response(type: .gameData, encodedContent: Data("to player".utf8))
        }
        await player.networkModel.connectionController?.request(type: .gameData, encodedContent: Data("to master".utf8))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if masterDelegate.calledReceived > masterReceived, playerDelegate.calledReceived > playerReceived { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        Logger.networking.error("E2E: master received \(masterDelegate.calledReceived - masterReceived), player received \(playerDelegate.calledReceived - playerReceived), master connections \(master.networkModel.connections.count)")
        return false
    }

    private func waitFor(_ state: PlayerNetworkModel.ConnectionState, of player: PlayerNetworkController, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if player.networkModel.connectionState == state { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test("Joining with a different code fails as a bad code")
    func joinWithWrongCode() async throws {
        let (master, game) = try await makeHost(code: "4821")
        defer { master.stopStreaming() }
        let player = PlayerNetworkController(name: "Player", delegate: PlayerNetworkControllerDelegateSpyingStub())

        let joined = await player.toggleConnection(to: game, passcode: "1111")
        await player.stop()

        #expect(!joined)
        #expect(player.networkModel.joinFailure != nil)
    }
}
#endif
