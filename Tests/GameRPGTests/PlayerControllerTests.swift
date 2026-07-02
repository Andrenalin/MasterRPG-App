// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
import PhotoRPG
import AdventureRPG

/// Test environment for PlayerController tests.
struct PlayerControllerTestEnvironment {
    let playerController: PlayerController
    let root: GameRoot
    let gameConfig: GameConfigModel
    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: GameNetworkController

    /// Creates a PlayerController with test dependencies
    static func create() async throws -> PlayerControllerTestEnvironment {
        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = await MasterNetworkControllableMock()
        let playerNetworkSpy = await PlayerStoreAbstractionMock()

        let networkController = await GameNetworkController(
            name: "Hello Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        await networkController.model.setMasterDelegate(masterDelegateSpy)
        await networkController.model.setPlayerDelegate(playerDelegateSpy)

        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        await MainActor.run {
            root.networkStore = networkController
        }
        let playerId = UUID()
        let gameConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let gameRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")])
        await root.gameModel.reset(gameConfig: gameConfig, gameRoster: gameRoster)

        let playerController = await PlayerController(root: root, asGameMaster: false)

        return PlayerControllerTestEnvironment(
            playerController: playerController,
            root: root,
            gameConfig: gameConfig,
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController
        )
    }
}

@Suite("Player controller tests")
struct PlayerControllerTests {

    @Test("Handle photo reveal with data and ID")
    func handlePhoto() async throws {
        // Arrange
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        await env.root.adventureRoot.startGame()

        await #expect(env.root.photoRoot.itemControllable.itemDataModel.items.count == 32)
        let itemId = await env.root.photoRoot.itemControllable.itemDataModel.items[0]
        let netData = try await env.root.photoRoot.gameControllable.createGameData(for: itemId)
        let netId = await env.root.photoRoot.gameControllable.share(id: itemId)

        // Act & Assert - Handle photo with full data
        var gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: env.gameConfig,
            data: netData
        )

        var result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        await #expect(env.root.photoRoot.gameControllable.currentId == itemId)

        // Act & Assert - Reset and handle with ID only
        await env.root.photoRoot.gameControllable.reset()
        await #expect(env.root.photoRoot.gameControllable.currentId != itemId)
        let item = await env.root.photoRoot.itemControllable.item(for: itemId)
        await env.root.photoRoot.itemControllable.itemDataModel.resetModel(id: itemId)

        gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: env.gameConfig,
            data: netId
        )
        result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .show)
        await #expect(env.root.photoRoot.gameControllable.currentId != itemId)

        // Act & Assert - Handle with data again
        gameNetworkModel = GameNetworkModel(
            version: 1,
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: env.gameConfig,
            data: netData
        )
        result = try await env.playerController.handle(gameNetworkModel)
        #expect(result?.subType == .ok)
        await #expect(env.root.photoRoot.gameControllable.currentId == itemId)
        await #expect(env.root.photoRoot.itemControllable.item(for: itemId) != nil)
        await #expect(env.root.photoRoot.itemControllable.item(for: itemId)?.name == item?.name)
    }
}
#endif
