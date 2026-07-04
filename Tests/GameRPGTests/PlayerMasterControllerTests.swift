// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG

@testable import DiceRPG
@testable import AudioRPG
@testable import MapRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import CharacterRPG
import AdventureRPG

/// Test environment for PlayerMasterController integration tests.
@MainActor
struct PlayerMasterControllerTestEnvironment {
    let master: MasterController
    let masterRoot: GameRoot
    let masterGameConfig: GameConfigModel
    let player: PlayerController
    let playerRoot: GameRoot
    let playerGameConfig: GameConfigModel
    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let network: GameNetworkController

    /// Creates a player-to-master test environment with full network setup
    static func create() async throws -> PlayerMasterControllerTestEnvironment {
        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = MasterNetworkControllableMock()
        let playerNetworkSpy = PlayerStoreAbstractionMock()

        let network = GameNetworkController(
            name: "Hello Test",
            proxy: false,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        network.model.setMasterDelegate(masterDelegateSpy)
        network.model.setPlayerDelegate(playerDelegateSpy)

        let networkProxy = GameNetworkController(
            name: "Hello Test",
            proxy: true,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )

        // Setup master
        let masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        await MainActor.run {
            masterRoot.networkStore = network
            masterRoot.networkProxyStore = networkProxy
        }

        let masterId = UUID()
        let masterGameConfig = GameConfigModel(id: masterId, state: .started, master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin"))
        masterRoot.gameModel.reset(gameConfig: masterGameConfig)
        let master = MasterController(root: masterRoot, asProxy: false)

        // Setup player
        let playerRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: playerRoot.adventureRoot)
        try await MockRoot.resetGameController(for: playerRoot)
        await MainActor.run {
            playerRoot.networkStore = network
        }

        let playerId = UUID()
        let playerGameConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")])
        playerRoot.gameModel.reset(gameConfig: playerGameConfig, gameRoster: playerRoster)
        let player = PlayerController(root: playerRoot, asGameMaster: false)

        return PlayerMasterControllerTestEnvironment(
            master: master,
            masterRoot: masterRoot,
            masterGameConfig: masterGameConfig,
            player: player,
            playerRoot: playerRoot,
            playerGameConfig: playerGameConfig,
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            network: network
        )
    }
}

@Suite("Player to master controller integration tests")
@MainActor
struct PlayerMasterControllerTests {

    @Test("Player sends audio to master and receives it back")
    func handleAudio() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 0)
        #expect(env.playerRoot.audioRoot.itemController.itemDataModel.items.count == 12)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let audioId = env.playerRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = env.playerRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        #expect(env.playerRoot.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)
        #expect(await env.playerRoot.audioRoot.gameController.currentId != audioId)

        // Act - Player sends audio to master
        let audioShareData = try await env.playerRoot.audioRoot.gameController.createGameData(for: audioId)
        await env.player.game(message: audioShareData, actionType: .generic)
        let sendedAudioData = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(nil != sendedAudioData)

        // Assert - Master receives and processes audio
        let result = try await env.master.handle(sendedAudioData!)
        #expect(nil == result)
        let resendAudioData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(resendAudioData!.type == .reveal)
        #expect(resendAudioData!.subType == .show)
        #expect(resendAudioData!.data.type == .audio)
        #expect(await env.masterRoot.audioRoot.gameController.currentId == audioId)
        #expect(env.masterRoot.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(env.masterRoot.audioRoot.itemController.itemDataModel.items.count == 1)
        #expect(await env.playerRoot.audioRoot.gameController.currentId != audioId)

        // Act - Player receives audio back from master
        let playerResult = try await env.player.handle(resendAudioData!)

        // Assert - Player now has audio displayed
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        #expect(await env.playerRoot.audioRoot.gameController.currentId == audioId)
        #expect(env.playerRoot.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(env.playerRoot.audioRoot.itemController.itemDataModel.items.count == 12)
    }

    @Test("Player sends photo to master and receives it back")
    func handlePhoto() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 6)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let photoId = env.playerRoot.photoRoot.itemController.itemDataModel.items[0]
        let version = env.playerRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version
        #expect(await env.playerRoot.photoRoot.gameController.currentId != photoId)

        // Act - Player sends photo to master
        let photoShareData = try await env.playerRoot.photoRoot.gameController.createGameData(for: photoId)
        await env.player.game(message: photoShareData, actionType: .generic)
        let sendedPhotoData = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(nil != sendedPhotoData)

        // Assert - Master receives and processes photo
        let result = try await env.master.handle(sendedPhotoData!)
        #expect(nil == result)
        let resendPhotoData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(resendPhotoData!.type == .reveal)
        #expect(resendPhotoData!.subType == .show)
        #expect(resendPhotoData!.data.type == .photo)
        #expect(await env.masterRoot.photoRoot.gameController.currentId == photoId)
        #expect(env.masterRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.count == 1)
        #expect(await env.playerRoot.photoRoot.gameController.currentId != photoId)

        // Act - Player receives photo back from master
        let playerResult = try await env.player.handle(resendPhotoData!)

        // Assert - Player now has photo displayed
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        #expect(await env.playerRoot.photoRoot.gameController.currentId == photoId)
        #expect(env.playerRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 6)
    }

    @Test("Player sends space to master and receives it back")
    func handleSpace() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.spaceTestData, itemCounter: 0)
        #expect(env.playerRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let spaceId = env.playerRoot.spaceRoot.itemController.itemDataModel.items[0]
        let version = env.playerRoot.spaceRoot.itemController.itemOrEmpty(for: spaceId).version
        #expect(await env.playerRoot.spaceRoot.gameController.currentId != spaceId)

        // Act - Player sends space to master
        let spaceShareData = try await env.playerRoot.spaceRoot.gameController.createGameData(for: spaceId)
        await env.player.game(message: spaceShareData, actionType: .generic)
        let sendedSpaceData = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(nil != sendedSpaceData)

        // Assert - Master receives and processes space
        let result = try await env.master.handle(sendedSpaceData!)
        #expect(nil == result)
        let resendSpaceData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(resendSpaceData!.type == .reveal)
        #expect(resendSpaceData!.subType == .show)
        #expect(resendSpaceData!.data.type == .space)
        #expect(await env.masterRoot.spaceRoot.gameController.currentId == spaceId)
        #expect(env.masterRoot.spaceRoot.gameController.gameItem(for: spaceId).version == version)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        #expect(await env.playerRoot.spaceRoot.gameController.currentId != spaceId)

        // Act - Player receives space back from master
        let playerResult = try await env.player.handle(resendSpaceData!)

        // Assert - Player now has space displayed
        #expect(nil != playerResult)
        #expect(playerResult!.subType == .ok)
        #expect(await env.playerRoot.spaceRoot.gameController.currentId == spaceId)
        #expect(env.playerRoot.spaceRoot.gameController.gameItem(for: spaceId).version == version)
        #expect(env.playerRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test("Player sends character update to master")
    func handleCharacterUpdate() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot)
        #expect(env.playerRoot.characterRoot.itemController.itemDataModel.items.count == 13)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let characterId = env.playerRoot.characterRoot.itemController.itemDataModel.items[1]
        var master = env.masterRoot.gameModel.gameConfig.master
        master.characterId = characterId
        env.masterRoot.gameModel.reset(master: master)
        let photoId = env.playerRoot.characterRoot.itemController.itemOrEmpty(for: characterId).photoId
        #expect(nil != photoId)

        // Act - Player sends character update to master
        let characterData = try? await env.playerRoot.characterRoot.gameControllable.createGameData(for: characterId)
        #expect(nil != characterData)
        await env.player.send(counter: 0, type: .update, subType: .store, updated: characterData!, useJournal: true)
        let sendedCharacterData = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(nil != sendedCharacterData)

        // Assert - Master receives and stores character
        var result = try await env.master.handle(sendedCharacterData!)
        #expect(nil == result)
        #expect(env.masterRoot.characterRoot.itemController.itemDataModel.items.count == 6)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.contains(photoId!))

        // Act - Send same character update again
        result = try await env.master.handle(sendedCharacterData!)

        // Assert - Master handles duplicate update gracefully
        #expect(nil == result)
        #expect(env.masterRoot.characterRoot.itemController.itemDataModel.items.count == 6)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.contains(photoId!))
    }
}
#endif
