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

    @Test("Available player reveals photo and master forwards only to its local player")
    func handlePhoto() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        #expect(env.playerRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let photoId = try #require(env.playerRoot.photoRoot.itemController.itemDataModel.items.first {
            env.playerRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.contains(photoId))
        let version = await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId)
        #expect(await env.playerRoot.photoRoot.gameController.networkVersion(for: photoId) == version)

        let playerId = env.playerGameConfig.id
        env.playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: playerId,
                state: .started,
                master: env.masterGameConfig.master
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")
            ])
        )

        // Report the player's versions first. The master answers with the
        // authoritative matrix whose own asset versions are the baseline.
        await env.player.sendPhotoList()
        let playerReport = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(playerReport.type == .update)
        #expect(playerReport.subType == .photoList)
        _ = try await env.master.handle(playerReport)

        let authoritativeReport = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(authoritativeReport.type == .update)
        #expect(authoritativeReport.subType == .photoList)
        _ = try await env.player.handle(authoritativeReport)

        env.masterNetworkSpy.sendResponseData = nil
        env.masterNetworkSpy.sendResponseHistory.removeAll()
        let masterBroadcastCount = env.masterNetworkSpy.calledSendResponseAll
        let localDeliveryCount = env.playerDelegateSpy.calledReceived

        // All reported participants have the exact baseline, so this reveal is
        // a reference. The transport already fans it out to remote peers; the
        // master only replays it to the co-located PlayerController.
        let photoShareData = try await env.playerRoot.photoRoot.gameController.createGameData(for: photoId)
        await env.player.game(message: photoShareData, actionType: .generic)
        let sentPhotoData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentPhotoData.type == .reveal)
        #expect(sentPhotoData.subType == .show)
        #expect(sentPhotoData.data.id == photoId)
        #expect(sentPhotoData.data.type == .photo)
        #expect(sentPhotoData.data.effectiveAssetVersion == version)
        #expect(sentPhotoData.data.data == nil)

        env.network.setupLocal()
        env.network.model.setPlayerDelegate(env.playerDelegateSpy)
        let result = try await env.master.handle(sentPhotoData)

        #expect(result == nil)
        #expect(env.masterNetworkSpy.calledSendResponseAll == masterBroadcastCount)
        #expect(env.masterNetworkSpy.sendResponseHistory.isEmpty)
        #expect(env.playerDelegateSpy.calledReceived == localDeliveryCount + 1)
        #expect(await env.masterRoot.photoRoot.gameController.currentId != photoId)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        #expect(await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId) == version)
        #expect(await env.playerRoot.photoRoot.gameController.currentId == photoId)
    }

    @Test("Available player reveals PDF and master forwards only to its local player")
    func handlePdf() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.pdfTestData, itemCounter: 0)
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.pdfTestData, itemCounter: 0)
        #expect(env.masterRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
        #expect(env.playerRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let pdfId = try #require(env.playerRoot.pdfRoot.itemController.itemDataModel.items.first {
            env.playerRoot.pdfRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        #expect(env.masterRoot.pdfRoot.itemController.itemDataModel.items.contains(pdfId))
        let version = await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId)
        #expect(await env.playerRoot.pdfRoot.gameController.networkVersion(for: pdfId) == version)

        let playerId = env.playerGameConfig.id
        env.playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: playerId,
                state: .started,
                master: env.masterGameConfig.master
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")
            ])
        )

        // Report the player's versions first. The master answers with the
        // authoritative matrix whose own PDF versions are the baseline.
        await env.player.sendPdfList()
        let playerReport = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(playerReport.type == .update)
        #expect(playerReport.subType == .pdfList)
        _ = try await env.master.handle(playerReport)

        let authoritativeReport = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(authoritativeReport.type == .update)
        #expect(authoritativeReport.subType == .pdfList)
        _ = try await env.player.handle(authoritativeReport)

        env.masterNetworkSpy.sendResponseData = nil
        env.masterNetworkSpy.sendResponseHistory.removeAll()
        let masterBroadcastCount = env.masterNetworkSpy.calledSendResponseAll
        let localDeliveryCount = env.playerDelegateSpy.calledReceived

        // Every reported participant has the baseline, so the player sends a
        // reference. Remote transports already fan it out; the master only
        // delivers it to the co-located player.
        let pdfShareData = try await env.playerRoot.pdfRoot.gameController.createGameData(for: pdfId)
        await env.player.game(message: pdfShareData, actionType: .generic)
        let sentPdfData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentPdfData.type == .reveal)
        #expect(sentPdfData.subType == .show)
        #expect(sentPdfData.data.id == pdfId)
        #expect(sentPdfData.data.type == .pdf)
        #expect(sentPdfData.data.effectiveAssetVersion == version)
        #expect(sentPdfData.data.data == nil)

        env.network.setupLocal()
        env.network.model.setPlayerDelegate(env.playerDelegateSpy)
        let result = try await env.master.handle(sentPdfData)

        #expect(result == nil)
        #expect(env.masterNetworkSpy.calledSendResponseAll == masterBroadcastCount)
        #expect(env.masterNetworkSpy.sendResponseHistory.isEmpty)
        #expect(env.playerDelegateSpy.calledReceived == localDeliveryCount + 1)
        #expect(await env.masterRoot.pdfRoot.gameController.currentId != pdfId)
        #expect(env.masterRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
        #expect(await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId) == version)
        #expect(await env.playerRoot.pdfRoot.gameController.currentId == pdfId)
    }

    @Test("Player PDF version mismatch makes master reveal its canonical asset")
    func mismatchedPlayerPdfUsesMasterCanonicalAsset() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.pdfTestData, itemCounter: 0)
        #expect(env.masterRoot.pdfRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()

        let pdfId = try #require(env.masterRoot.pdfRoot.itemController.itemDataModel.items.first {
            env.masterRoot.pdfRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let canonical = try await env.masterRoot.pdfRoot.gameController.createGameData(for: pdfId)
        let masterVersion = canonical.effectiveAssetVersion
        let competingVersion = masterVersion + 1
        let playerConfig = GameConfigModel(
            id: env.playerGameConfig.id,
            state: .started,
            master: env.masterGameConfig.master
        )
        let competingBytes = Data("player-owned-competing-pdf".utf8)
        let competingReveal = GameNetworkModel(
            version: 1,
            counter: 16,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: playerConfig,
            data: NetworkCodableDataType(
                id: pdfId,
                type: .pdf,
                version: competingVersion,
                data: competingBytes
            )
        )

        let result = try await env.master.handle(competingReveal)

        #expect(result == nil)
        let resent = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resent.type == .reveal)
        #expect(resent.subType == .show)
        #expect(resent.data.id == pdfId)
        #expect(resent.data.type == .pdf)
        #expect(resent.data.effectiveAssetVersion == masterVersion)
        #expect(resent.data.data != nil)
        #expect(resent.data.data != competingBytes)
        #expect(await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId) == masterVersion)
        #expect(await env.masterRoot.pdfRoot.gameController.currentId != pdfId)
    }

    @Test("Player photo version mismatch makes master reveal its canonical asset")
    func mismatchedPlayerPhotoUsesMasterCanonicalAsset() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.count == 3)
        env.masterRoot.adventureRoot.startGame()

        let photoId = try #require(env.masterRoot.photoRoot.itemController.itemDataModel.items.first {
            env.masterRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
        let canonical = try await env.masterRoot.photoRoot.gameController.createGameData(for: photoId)
        let masterVersion = canonical.effectiveAssetVersion
        let competingVersion = masterVersion + 1
        let playerConfig = GameConfigModel(
            id: env.playerGameConfig.id,
            state: .started,
            master: env.masterGameConfig.master
        )
        let competingBytes = Data("player-owned-competing-photo".utf8)
        let competingReference = NetworkCodableDataType(
            id: photoId,
            type: .photo,
            version: competingVersion,
            data: competingBytes
        )
        let reveal = GameNetworkModel(
            version: 1,
            counter: 17,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: playerConfig,
            data: competingReference
        )

        let result = try await env.master.handle(reveal)

        #expect(result == nil)
        let resent = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resent.type == .reveal)
        #expect(resent.subType == .show)
        #expect(resent.data.id == photoId)
        #expect(resent.data.type == .photo)
        #expect(resent.data.effectiveAssetVersion == masterVersion)
        #expect(resent.data.data != nil)
        #expect(resent.data.data != competingBytes)
        #expect(await env.masterRoot.photoRoot.gameController.networkVersion(for: photoId) == masterVersion)
        #expect(await env.masterRoot.photoRoot.gameController.currentId != photoId)
    }

    @Test("Available player reveals Space and master forwards only to its local player")
    func handleSpace() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.spaceTestData, itemCounter: 0)
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.spaceTestData, itemCounter: 0)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        #expect(env.playerRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let spaceId = try #require(env.playerRoot.spaceRoot.itemController.itemDataModel.items.first)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.contains(spaceId))
        let version = await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId)
        #expect(await env.playerRoot.spaceRoot.gameController.networkVersion(for: spaceId) == version)

        let playerId = env.playerGameConfig.id
        env.playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: playerId,
                state: .started,
                master: env.masterGameConfig.master
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")
            ])
        )

        // Report the player's versions first. The master answers with the
        // authoritative matrix whose own Space versions are the baseline.
        await env.player.sendSpaceList()
        let playerReport = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(playerReport.type == .update)
        #expect(playerReport.subType == .spaceList)
        _ = try await env.master.handle(playerReport)

        let authoritativeReport = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(authoritativeReport.type == .update)
        #expect(authoritativeReport.subType == .spaceList)
        _ = try await env.player.handle(authoritativeReport)

        env.masterNetworkSpy.sendResponseData = nil
        env.masterNetworkSpy.sendResponseHistory.removeAll()
        let masterBroadcastCount = env.masterNetworkSpy.calledSendResponseAll
        let localDeliveryCount = env.playerDelegateSpy.calledReceived

        // Every reported participant has the baseline, so the player sends a
        // reference. Remote transports already fan it out; the master only
        // delivers it to the co-located player.
        let spaceShareData = try await env.playerRoot.spaceRoot.gameController.createGameData(for: spaceId)
        await env.player.game(message: spaceShareData, actionType: .generic)
        let sentSpaceData = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        #expect(sentSpaceData.type == .reveal)
        #expect(sentSpaceData.subType == .show)
        #expect(sentSpaceData.data.id == spaceId)
        #expect(sentSpaceData.data.type == .space)
        #expect(sentSpaceData.data.effectiveAssetVersion == version)
        #expect(sentSpaceData.data.data == nil)

        env.network.setupLocal()
        env.network.model.setPlayerDelegate(env.playerDelegateSpy)
        let result = try await env.master.handle(sentSpaceData)

        #expect(result == nil)
        #expect(env.masterNetworkSpy.calledSendResponseAll == masterBroadcastCount)
        #expect(env.masterNetworkSpy.sendResponseHistory.isEmpty)
        #expect(env.playerDelegateSpy.calledReceived == localDeliveryCount + 1)
        #expect(await env.masterRoot.spaceRoot.gameController.currentId != spaceId)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        #expect(await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId) == version)
        #expect(await env.playerRoot.spaceRoot.gameController.currentId == spaceId)
    }

    @Test("Player Space version mismatch makes master reveal its canonical asset")
    func mismatchedPlayerSpaceUsesMasterCanonicalAsset() async throws {
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.spaceTestData, itemCounter: 0)
        #expect(env.masterRoot.spaceRoot.itemController.itemDataModel.items.count == 1)
        env.masterRoot.adventureRoot.startGame()

        let spaceId = try #require(env.masterRoot.spaceRoot.itemController.itemDataModel.items.first)
        let canonical = try await env.masterRoot.spaceRoot.gameController.createGameData(for: spaceId)
        let masterVersion = canonical.effectiveAssetVersion
        let competingVersion = masterVersion + 1
        let playerConfig = GameConfigModel(
            id: env.playerGameConfig.id,
            state: .started,
            master: env.masterGameConfig.master
        )
        let competingBytes = Data("player-owned-competing-space".utf8)
        let competingReveal = GameNetworkModel(
            version: 1,
            counter: 18,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: playerConfig,
            data: NetworkCodableDataType(
                id: spaceId,
                type: .space,
                version: competingVersion,
                data: competingBytes
            )
        )

        // The player has not reported a matching master baseline, and its bytes
        // claim a competing version. This is a request for the master's asset,
        // never an import that can replace it.
        let result = try await env.master.handle(competingReveal)

        #expect(result == nil)
        let resent = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(resent.type == .reveal)
        #expect(resent.subType == .show)
        #expect(resent.data.id == spaceId)
        #expect(resent.data.type == .space)
        #expect(resent.data.effectiveAssetVersion == masterVersion)
        #expect(resent.data.data != nil)
        #expect(resent.data.data != competingBytes)
        #expect(await env.masterRoot.spaceRoot.gameController.networkVersion(for: spaceId) == masterVersion)
        #expect(await env.masterRoot.spaceRoot.gameController.currentId != spaceId)
    }

    @Test("Master requests and imports a Character package only after a version mismatch")
    func characterJoinHandshake() async throws {
        // Given
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let characterId = try #require(
            env.playerRoot.characterRoot.itemController.itemDataModel.items.first {
                let item = env.playerRoot.characterRoot.itemController.itemOrEmpty(for: $0)
                return item.category == .character && item.photoId != nil
            }
        )
        let playerCharacter = env.playerRoot.characterRoot.itemController.itemOrEmpty(for: characterId)
        let photoId = try #require(playerCharacter.photoId)
        env.playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(
                id: env.playerGameConfig.id,
                state: .started,
                master: env.masterGameConfig.master
            ),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(
                    id: env.playerGameConfig.id,
                    type: .player,
                    name: "AndrenalinPlayer",
                    characterId: characterId
                ),
            ])
        )
        env.player.gameModel.lostMaster = false

        // When: the player advertises only ID and version.
        await env.player.sendCharacter()
        let reference = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)

        // Then: a missing Character makes the master request the package.
        #expect(reference.data.data == nil)
        #expect(reference.data.version != 0)
        let requestedData = try #require(try await env.master.handle(reference))
        #expect(requestedData == reference.data)

        // When: the targeted request reaches the player.
        let request = env.masterRoot.gameModel.outgoingMessage(
            counter: reference.counter,
            type: .update,
            subType: .store,
            asMaster: true,
            targetId: env.playerGameConfig.id,
            data: requestedData
        )
        _ = try await env.player.handle(request)
        let messages = env.playerNetworkSpy.requestHistory.compactMap { $0 as? GameNetworkModel }
        let package = try #require(messages.last)
        #expect(messages.count == 2)
        #expect(package.data.data != nil)
        #expect(package.data.version == reference.data.version)
        #expect(!PlayerController.usesFileJournal(for: package))

        // Then: the master imports the recursive package, including the pin photo.
        let importResponse = try await env.master.handle(package)
        #expect(importResponse == nil)
        let masterCharacter = try #require(await env.masterRoot.characterRoot.itemController.item(for: characterId))
        #expect(masterCharacter.name == playerCharacter.name)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.contains(photoId))
        #expect(await env.masterRoot.characterRoot.gameControllable.networkVersion(for: characterId) == reference.data.version)

        // And: the same metadata now needs no package request.
        let matchingResponse = try await env.master.handle(reference)
        #expect(matchingResponse == nil)
    }
}
#endif
