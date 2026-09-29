// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

@Suite("Player network controller lifecycle tests")
@MainActor
struct PlayerNetworkControllerTests {
    @Test("Callbacks from a replaced connection are ignored")
    func replacedConnectionCallbacksAreIgnored() async {
        // Arrange
        let delegateSpy = PlayerNetworkControllerDelegateSpyingStub()
        let controller = PlayerNetworkController(name: "Player", delegate: delegateSpy)
        controller.networkModel.playerConnectionId = UUID()
        let replacedID = UUID()
        let activeID = UUID()
        controller.networkModel.reset(
            controller: makeConnection(id: replacedID, delegate: controller)
        )
        controller.networkModel.reset(
            controller: makeConnection(id: activeID, delegate: controller)
        )
        let data = Data([0x01])

        // Act
        await controller.readyConnection(for: replacedID)
        await controller.received(data: data, for: replacedID)
        await controller.failed(with: "Late failure", for: replacedID)
        await controller.lostConnection(for: replacedID)

        // Assert
        #expect(controller.networkModel.connectionController?.id == activeID)
        #expect(controller.networkModel.playerConnectionId != nil)
        #expect(!controller.networkModel.isConnected)
        #expect(controller.networkModel.connectionState == .notReady)
        #expect(delegateSpy.calledReady == 0)
        #expect(delegateSpy.calledReceived == 0)
        #expect(delegateSpy.calledLostMaster == 0)
    }

    @Test("Callbacks from the active replacement connection are accepted")
    func activeReplacementCallbacksAreAccepted() async {
        // Arrange
        let delegateSpy = PlayerNetworkControllerDelegateSpyingStub()
        let controller = PlayerNetworkController(name: "Player", delegate: delegateSpy)
        controller.networkModel.playerConnectionId = UUID()
        let activeID = UUID()
        controller.networkModel.reset(
            controller: makeConnection(id: activeID, delegate: controller)
        )
        let data = Data([0x02])

        // Act
        await controller.readyConnection(for: activeID)
        await controller.received(data: data, for: activeID)

        // Assert
        #expect(controller.networkModel.isConnected)
        #expect(controller.networkModel.connectionState == .ready)
        #expect(delegateSpy.calledReady == 1)
        #expect(delegateSpy.calledReceived == 1)
        #expect(delegateSpy.calledLostMaster == 0)
    }

    private func makeConnection(
        id: ConnectionController.ID,
        delegate: any ConnectionControllerDelegate
    ) -> ConnectionController {
        ConnectionController(
            id: id,
            connection: .game(to: .hostPort(host: "localhost", port: .any), passcode: "1234"),
            delegate: delegate
        )
    }
}
#endif
