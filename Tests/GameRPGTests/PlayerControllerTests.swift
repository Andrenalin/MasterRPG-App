// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
@testable import CharacterRPG
import PhotoRPG
import AdventureRPG
@testable import WeatherRPG

/// Test environment for PlayerController tests.
@MainActor
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

        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        await MainActor.run {
            root.networkStore = networkController
        }
        let playerId = UUID()
        let gameConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let gameRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")])
        root.gameModel.reset(gameConfig: gameConfig, gameRoster: gameRoster)

        let playerController = PlayerController(root: root, asGameMaster: false)

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
@MainActor
struct PlayerControllerTests {

    @Test("Handle photo reveal with data and ID")
    func handlePhoto() async throws {
        // Arrange
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        env.root.adventureRoot.startGame()

        #expect(env.root.photoRoot.itemControllable.itemDataModel.items.count == 32)
        let itemId = env.root.photoRoot.itemControllable.itemDataModel.items[0]
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
        #expect(await env.root.photoRoot.gameControllable.currentId == itemId)

        // Act & Assert - Reset and handle with ID only
        await env.root.photoRoot.gameControllable.reset()
        #expect(await env.root.photoRoot.gameControllable.currentId != itemId)
        let item = await env.root.photoRoot.itemControllable.item(for: itemId)
        env.root.photoRoot.itemControllable.itemDataModel.resetModel(id: itemId)

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
        #expect(await env.root.photoRoot.gameControllable.currentId != itemId)

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
        #expect(await env.root.photoRoot.gameControllable.currentId == itemId)
        let restoredItem = await env.root.photoRoot.itemControllable.item(for: itemId)
        #expect(restoredItem != nil)
        #expect(restoredItem?.name == item?.name)
    }

    @Test("Handle value reveal, store, item update and result update from master")
    func handleValueFromMaster() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController

        let characterId = await root.characterRoot.itemController.addNew(type: .character)
        root.characterRoot.editController.reset(name: "Mira", itemId: characterId)
        let itemId = await root.characterRoot.itemController.addNew(type: .item)
        root.characterRoot.editController.reset(name: "Lantern", itemId: itemId)
        root.gameModel.reset(
            gameConfig: env.gameConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: env.gameConfig.id, type: .player, name: "AndrenalinPlayer", characterId: characterId)
            ])
        )

        let masterConfig = Self.masterConfig()
        let characterData = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        var response = try await sut.handle(Self.networkModel(type: .reveal, data: characterData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)
        #expect(await root.characterRoot.gameControllable.currentId == characterId)
        #expect(sut.gameModel.gameUpdateType == .value)

        let missingId = UUID()
        let missingData = NetworkCodableDataType(id: missingId, type: .value, version: 1)
        response = try await sut.handle(Self.networkModel(type: .reveal, data: missingData, gameConfig: masterConfig))
        #expect(response?.subType == .show)
        #expect(response?.data.id == missingId)

        response = try await sut.handle(Self.networkModel(type: .store, subType: .store, data: characterData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)

        let itemData = try await root.characterRoot.gameControllable.createGameData(for: itemId)
        response = try await sut.handle(Self.networkModel(type: .update, subType: .generic, data: itemData, gameConfig: masterConfig))
        #expect(response == nil)

        let resultData = root.characterRoot.valueGameControllable.create(
            name: "Clue",
            value: "The door is warm",
            resultCategory: ResultCategory(id: UUID(), module: .value)
        )
        response = try await sut.handle(Self.networkModel(type: .update, subType: .valueResult, data: resultData, gameConfig: masterConfig))
        #expect(response == nil)

        let playerConfig = Self.playerConfig(masterId: masterConfig.master.id)
        response = try await sut.handle(Self.networkModel(type: .update, subType: .generic, data: itemData, gameConfig: playerConfig))
        #expect(response == nil)
    }

    @Test("Handle proxy value update focuses the forwarded character")
    func handleProxyValueUpdateFocusesCharacter() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController

        let characterId = await root.characterRoot.itemController.addNew(type: .character)
        root.characterRoot.editController.reset(name: "Proxy Mira", itemId: characterId)
        root.gameModel.reset(
            gameConfig: env.gameConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: env.gameConfig.id, type: .proxy, name: "Proxy Player", characterId: characterId)
            ])
        )

        let characterData = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        let response = try await sut.handle(Self.networkModel(type: .update, subType: .store, data: characterData, gameConfig: Self.masterConfig()))
        #expect(response == nil)
        #expect(sut.gameModel.proxyFocusTask != nil)

        try await Task.sleep(for: .milliseconds(1_100))
        #expect(root.gameModel.selectedCharacter == characterId)
        #expect(sut.gameModel.proxyFocusTask == nil)
    }

    @Test("Handle weather reveal, store and update messages")
    func handleWeather() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let root = env.root
        let sut = env.playerController
        let masterConfig = Self.masterConfig()

        let weatherId = await root.weatherRoot.itemController.addNew(type: .scenario)
        root.weatherRoot.editController.reset(name: "Storm Front", itemId: weatherId)
        let weatherData = try await root.weatherRoot.gameControllable.createGameData(for: weatherId)

        var response = try await sut.handle(Self.networkModel(type: .reveal, data: weatherData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)
        #expect(await root.weatherRoot.gameControllable.currentId == weatherId)
        #expect(sut.gameModel.gameUpdateType == .weather)

        let missingId = UUID()
        let missingData = NetworkCodableDataType(id: missingId, type: .weather, version: 1)
        response = try await sut.handle(Self.networkModel(type: .reveal, data: missingData, gameConfig: masterConfig))
        #expect(response?.subType == .show)
        #expect(response?.data.id == missingId)

        response = try await sut.handle(Self.networkModel(type: .store, subType: .store, data: weatherData, gameConfig: masterConfig))
        #expect(response?.subType == .ok)

        await root.weatherRoot.gameControllable.reset()
        response = try await sut.handle(Self.networkModel(type: .update, subType: .show, data: weatherData, gameConfig: masterConfig))
        #expect(response == nil)
        #expect(await root.weatherRoot.gameControllable.currentId == weatherId)
        #expect(sut.gameModel.gameUpdateType == .weather)
    }

    @Test("Player connection delegates update state and process master messages")
    func connectionDelegatesUpdateStateAndProcessMessages() async throws {
        let env = try await PlayerControllerTestEnvironment.create()
        let sut = env.playerController
        let masterConfig = Self.masterConfig()
        let data = NetworkCodableDataType(id: UUID(), type: .none, version: 0)

        await sut.readyProxy()
        #expect(sut.gameModel.lostMaster == false)

        await sut.lostProxyConnection()
        #expect(sut.gameModel.lostMaster)
        #expect(sut.gameModel.hasSendPlayer == false)

        await sut.ready()
        #expect(sut.gameModel.lostMaster == false)
        await sut.lostConnection()
        #expect(sut.gameModel.lostMaster)
        #expect(sut.gameModel.sendCharacterTask == nil)

        await sut.received(Self.networkModel(counter: 21, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 1)

        await sut.receivedProxy(Self.networkModel(counter: 22, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 2)

        await sut.receivedFile(Self.networkModel(counter: 23, type: .update, data: data, gameConfig: masterConfig))
        #expect(sut.gameModel.messageCounter == 3)

        await sut.receivedFile(Self.networkModel(counter: 24, type: .update, data: data, gameConfig: env.gameConfig))
        #expect(sut.gameModel.messageCounter == 3)
    }
}

private extension PlayerControllerTests {
    static func masterConfig(id: UUID = UUID(), name: String = "Game Master") -> GameConfigModel {
        GameConfigModel(id: id, state: .started, master: MasterGameModel(id: id, type: .master, name: name))
    }

    static func playerConfig(masterId: UUID) -> GameConfigModel {
        GameConfigModel(id: UUID(), state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Game Master"))
    }

    static func networkModel(
        counter: Int = 1,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        data: NetworkCodableDataType,
        gameConfig: GameConfigModel
    ) -> GameNetworkModel {
        GameNetworkModel(
            version: 1,
            counter: counter,
            proxyCounter: 0,
            type: type,
            subType: subType,
            gameConfig: gameConfig,
            data: data
        )
    }
}
#endif
