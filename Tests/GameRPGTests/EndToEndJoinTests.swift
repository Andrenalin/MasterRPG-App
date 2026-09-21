// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// The real master and player controllers over real Bonjour + TLS-PSK on loopback.
@Suite("End-to-end LAN join")
@MainActor
struct EndToEndJoinTests {
    private func makeHost(code: String) async throws -> (MasterNetworkController, BrowserGameModel) {
        let name = "JoinTest-\(UUID().uuidString.prefix(8))"
        let master = MasterNetworkController(
            name: name,
            delegate: MasterNetworkControllerDelegateMock(),
            listnerBuilder: MasterNetworkController.gameListenerBuilder()
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
