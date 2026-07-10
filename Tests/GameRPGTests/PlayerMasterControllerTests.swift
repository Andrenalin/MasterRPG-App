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
@testable import PdfRPG
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
        #expect(env.playerRoot.audioRoot.itemController.itemDataModel.items.count == 2)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let audioId = try #require(env.playerRoot.audioRoot.itemController.itemDataModel.items.first {
            env.playerRoot.audioRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let version = env.playerRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        #expect(await env.playerRoot.audioRoot.gameController.currentId != audioId)

        // Act - Player sends audio to master
        let audioShareData = try await env.playerRoot.audioRoot.gameController.createGameData(for: audioId)
        await env.player.game(message: audioShareData, actionType: .generic)
        let sentAudioData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentAudioData.type == .update)
        #expect(sentAudioData.subType == .generic)
        #expect(sentAudioData.data.id == audioId)
        #expect(sentAudioData.data.type == .audio)

        // Assert - Master receives, persists, and sends audio back
        let result = try await env.master.handle(sentAudioData)
        #expect(nil == result)
        let resendAudioData = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resendAudioData.type == .reveal)
        #expect(resendAudioData.subType == .show)
        #expect(resendAudioData.data.id == audioId)
        #expect(resendAudioData.data.type == .audio)
        #expect(await env.masterRoot.audioRoot.gameController.currentId == audioId)
        #expect(env.masterRoot.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(env.masterRoot.audioRoot.itemController.itemDataModel.items.count == 1)
        let persistedAudio = try #require(env.masterRoot.audioRoot.itemController.itemSync(for: audioId, noGame: true))
        #expect(persistedAudio.version == version)
        #expect(persistedAudio.fileUrl != nil)
        #expect(await env.playerRoot.audioRoot.gameController.currentId != audioId)

        // Act - Player receives audio back from master
        let playerResult = try await env.player.handle(resendAudioData)

        // Assert - Player now has audio displayed
        let playerResponse = try #require(playerResult)
        #expect(playerResponse.subType == .ok)
        #expect(await env.playerRoot.audioRoot.gameController.currentId == audioId)
        #expect(env.playerRoot.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(env.playerRoot.audioRoot.itemController.itemDataModel.items.count == 2)
    }

    @Test("Player sends photo to master and receives it back")
    func handlePhoto() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let photoId = try #require(env.playerRoot.photoRoot.itemController.itemDataModel.items.first {
            env.playerRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let version = env.playerRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version
        #expect(await env.playerRoot.photoRoot.gameController.currentId != photoId)

        // Act - Player sends photo to master
        let photoShareData = try await env.playerRoot.photoRoot.gameController.createGameData(for: photoId)
        await env.player.game(message: photoShareData, actionType: .generic)
        let sentPhotoData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentPhotoData.type == .update)
        #expect(sentPhotoData.subType == .generic)
        #expect(sentPhotoData.data.id == photoId)
        #expect(sentPhotoData.data.type == .photo)

        // Assert - Master receives, persists, and sends photo back
        let result = try await env.master.handle(sentPhotoData)
        #expect(nil == result)
        let resendPhotoData = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resendPhotoData.type == .reveal)
        #expect(resendPhotoData.subType == .show)
        #expect(resendPhotoData.data.id == photoId)
        #expect(resendPhotoData.data.type == .photo)
        #expect(await env.masterRoot.photoRoot.gameController.currentId == photoId)
        #expect(env.masterRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.count == 1)
        let persistedPhoto = try #require(env.masterRoot.photoRoot.itemController.itemSync(for: photoId, noGame: true))
        #expect(persistedPhoto.version == version)
        #expect(persistedPhoto.fileUrl != nil)
        #expect(await env.playerRoot.photoRoot.gameController.currentId != photoId)

        // Act - Player receives photo back from master
        let playerResult = try await env.player.handle(resendPhotoData)

        // Assert - Player now has photo displayed
        let playerResponse = try #require(playerResult)
        #expect(playerResponse.subType == .ok)
        #expect(await env.playerRoot.photoRoot.gameController.currentId == photoId)
        #expect(env.playerRoot.photoRoot.gameController.gameItem(for: photoId).version == version)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 3)
    }

    @Test("Player sends pdf to master, master saves it, and player receives it back")
    func handlePdf() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.pdfTestData, itemCounter: 0)
        #expect(env.playerRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let pdfId = try #require(env.playerRoot.pdfRoot.itemController.itemDataModel.items.first {
            env.playerRoot.pdfRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let version = env.playerRoot.pdfRoot.itemController.itemOrEmpty(for: pdfId).version
        #expect(await env.playerRoot.pdfRoot.gameController.currentId != pdfId)

        // Act - Player sends pdf to master
        let pdfShareData = try await env.playerRoot.pdfRoot.gameController.createGameData(for: pdfId)
        await env.player.game(message: pdfShareData, actionType: .generic)
        let sentPdfData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentPdfData.type == .update)
        #expect(sentPdfData.subType == .generic)
        #expect(sentPdfData.data.id == pdfId)
        #expect(sentPdfData.data.type == .pdf)

        // Assert - Master receives, persists, and sends pdf back
        let result = try await env.master.handle(sentPdfData)
        #expect(nil == result)
        let resendPdfData = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resendPdfData.type == .reveal)
        #expect(resendPdfData.subType == .show)
        #expect(resendPdfData.data.id == pdfId)
        #expect(resendPdfData.data.type == .pdf)
        #expect(await env.masterRoot.pdfRoot.gameController.currentId == pdfId)
        #expect(env.masterRoot.pdfRoot.gameController.gameItem(for: pdfId).version == version)
        let persistedPdf = try #require(env.masterRoot.pdfRoot.itemController.itemSync(for: pdfId, noGame: true))
        #expect(persistedPdf.version == version)
        #expect(persistedPdf.fileUrl != nil)
        #expect(env.masterRoot.pdfRoot.itemController.itemDataModel.items.contains(pdfId))
        #expect(await env.playerRoot.pdfRoot.gameController.currentId != pdfId)

        // Act - Player receives pdf back from master
        let playerResult = try await env.player.handle(resendPdfData)

        // Assert - Player now has pdf displayed
        let playerResponse = try #require(playerResult)
        #expect(playerResponse.subType == .ok)
        #expect(await env.playerRoot.pdfRoot.gameController.currentId == pdfId)
        #expect(env.playerRoot.pdfRoot.gameController.gameItem(for: pdfId).version == version)
        #expect(env.playerRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test("Player sends multiple photos to master and master saves each one")
    func handleMultiplePhotos() async throws {
        // Arrange
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let photoIds = Array(env.playerRoot.photoRoot.itemController.itemDataModel.items.filter {
            env.playerRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        }.prefix(2))
        #expect(photoIds.count == 2)

        for photoId in photoIds {
            let version = env.playerRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version

            // Act - Player sends photo to master
            let photoShareData = try await env.playerRoot.photoRoot.gameController.createGameData(for: photoId)
            await env.player.game(message: photoShareData, actionType: .generic)
            let sentPhotoData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)

            // Assert - Master imports and persists the photo
            let result = try await env.master.handle(sentPhotoData)
            #expect(nil == result)
            #expect(await env.masterRoot.photoRoot.gameController.currentId == photoId)
            #expect(env.masterRoot.photoRoot.gameController.gameItem(for: photoId).version == version)

            let masterPhoto = try #require(env.masterRoot.photoRoot.itemController.itemSync(for: photoId, noGame: true))
            #expect(masterPhoto.version == version)
            #expect(masterPhoto.fileUrl != nil)
            #expect(masterPhoto.fileUrl?.contentHash != nil)
        }
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
        let sentSpaceData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentSpaceData.type == .update)
        #expect(sentSpaceData.subType == .generic)
        #expect(sentSpaceData.data.id == spaceId)
        #expect(sentSpaceData.data.type == .space)

        // Assert - Master receives, persists, and sends space back
        let result = try await env.master.handle(sentSpaceData)
        #expect(nil == result)
        let resendSpaceData = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resendSpaceData.type == .reveal)
        #expect(resendSpaceData.subType == .show)
        #expect(resendSpaceData.data.id == spaceId)
        #expect(resendSpaceData.data.type == .space)
        #expect(await env.masterRoot.spaceRoot.gameController.currentId == spaceId)
        #expect(env.masterRoot.spaceRoot.gameController.gameItem(for: spaceId).version == version)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        let persistedSpace = try #require(env.masterRoot.spaceRoot.itemController.itemSync(for: spaceId, noGame: true))
        #expect(persistedSpace.version == version)
        #expect(await env.playerRoot.spaceRoot.gameController.currentId != spaceId)

        // Act - Player receives space back from master
        let playerResult = try await env.player.handle(resendSpaceData)

        // Assert - Player now has space displayed
        let playerResponse = try #require(playerResult)
        #expect(playerResponse.subType == .ok)
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
