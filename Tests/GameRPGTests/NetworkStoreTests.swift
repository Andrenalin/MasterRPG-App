// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Network
import Testing

@testable import GameRPG

/// Test environment for NetworkController tests.
@MainActor
struct NetworkStoreTestEnvironment {
    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: GameNetworkController

    /// Creates a GameNetworkController with spy dependencies
    static func create() async throws -> NetworkStoreTestEnvironment {
        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()

        let networkController = GameNetworkController(
            name: "Hello Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        networkController.model.setMasterDelegate(masterDelegateSpy)
        networkController.model.setPlayerDelegate(playerDelegateSpy)

        return NetworkStoreTestEnvironment(
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController
        )
    }
}

@Suite("Network controller tests")
@MainActor
struct NetworkStoreTests {

    // Test data
    let masterGameNetworkModel = GameNetworkModel(
        counter: 1,
        proxyCounter: 0,
        type: .reveal,
        subType: .show,
        gameConfig: .master,
        data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
    )

    let playerGameNetworkModel = GameNetworkModel(
        counter: 2,
        proxyCounter: 0,
        type: .reveal,
        subType: .show,
        gameConfig: .player,
        data: NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
    )

    @Test("Master game network flow")
    func masterGame() async throws {
        // Arrange
        let env = try await NetworkStoreTestEnvironment.create()

        // Act & Assert - Start master game
        await env.networkController.startMasterGame(game: .master, titleImage: nil)
        #expect(env.masterNetworkSpy.calledStartStreaming == 1)

        // Act & Assert - Master ready
        await env.networkController.masterReady(for: ConnectionController.ID())
        #expect(env.masterDelegateSpy.calledReady == 1)

        // Act & Assert - Send to specific player (id registered as a direct connection)
        let connectionId = ConnectionController.ID()
        env.masterNetworkSpy.networkModel.registerTestConnection(id: connectionId)
        await env.networkController.sendPlayer(masterGameNetworkModel, to: connectionId)
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)

        // Act & Assert - Unknown id (e.g. a SharePlay participant) falls back to broadcast
        await env.networkController.sendPlayer(masterGameNetworkModel, to: ConnectionController.ID())
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 1)

        // Act & Assert - Send to all players
        await env.networkController.sendPlayer(data: masterGameNetworkModel, fileJournal: false)
        #expect(env.masterNetworkSpy.calledSendResponseAll == 2)

        // Act & Assert - Master received data
        await env.networkController.masterReceived(
            data: masterGameNetworkModel.encodeData(),
            for: ConnectionController.ID(),
            fileJournal: false
        )
        #expect(env.masterNetworkSpy.calledSendResponseExcept == 1)
        #expect(env.masterDelegateSpy.calledReceived == 1)

        // Act & Assert - Stop game when not streaming
        await env.networkController.stopGame()
        #expect(env.masterNetworkSpy.calledStopStreaming == 0)

        // Act & Assert - Stop game when streaming
        env.masterNetworkSpy.networkModel.reset(isStreaming: true)
        await env.networkController.stopGame()
        #expect(env.masterNetworkSpy.calledStopStreaming == 1)
    }

    @Test("Player game network flow")
    func playerGame() async throws {
        // Arrange
        let env = try await NetworkStoreTestEnvironment.create()

        // Act & Assert - Start player game with no device (should fail)
        let result = await env.networkController.startPlayerGame(to: nil)
        #expect(result == false)
        #expect(env.playerNetworkSpy.calledToggleConnection == 0)

        // Act & Assert - Start player game with device (should succeed)
        let connectResult = await env.networkController.startPlayerGame(
            to: BrowserGameModel(id: UUID(), endpointName: "MasterTestDevice", connectionMode: .observer)
        )
        #expect(connectResult)
        #expect(env.playerNetworkSpy.calledToggleConnection == 1)

        // Act & Assert - Player ready
        await env.networkController.playerReady()
        #expect(env.playerDelegateSpy.calledReady == 1)

        // Act & Assert - Send to master
        await env.networkController.sendMaster(data: playerGameNetworkModel, fileJournal: false)
        #expect(env.playerNetworkSpy.calledRequest == 1)

        // Act & Assert - Player received data
        await env.networkController.playerReceived(data: playerGameNetworkModel.encodeData())
        #expect(env.playerDelegateSpy.calledReceived == 1)

        // Act & Assert - Player lost master
        await env.networkController.playerLostMaster()
        #expect(env.playerDelegateSpy.calledLostConnection == 1)

        // Act & Assert - Stop game
        await env.networkController.stopGame()
        #expect(env.playerNetworkSpy.calledStop == 1)
    }
}
#endif
