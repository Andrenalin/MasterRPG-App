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
        // A package holds the item itself, not the other tracks of its playlist.
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

    @Test("Player contributes audio the master lacks and can play it afterwards")
    func contributedAudioBecomesPlayableOnThePlayer() async throws {
        // Given: one player owns a playlist the master has never seen.
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.playerRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 0)
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let playerId = env.playerGameConfig.id
        let roster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "AndrenalinPlayer")])
        let control = GameControlModel(controls: [SharingControlModel(id: playerId, name: "AndrenalinPlayer", show: true)])
        env.masterRoot.gameModel.gameRoster = roster
        env.masterRoot.gameModel.gameControl = control
        await env.master.resetPlayers()
        env.playerRoot.gameModel.reset(
            gameConfig: GameConfigModel(id: playerId, state: .started, master: env.masterGameConfig.master),
            gameRoster: roster
        )
        env.playerRoot.gameModel.gameControl = control
        env.player.resetPlayers()

        // A playlist: "everyone has it" asks for each of its tracks as well.
        let audioId = try #require(env.playerRoot.audioRoot.itemController.itemDataModel.items.first {
            env.playerRoot.audioRoot.itemController.itemSync(for: $0)?.entries.isEmpty == false
        })
        let playerAudio = env.playerRoot.audioRoot.gameController

        // The join handshake: the player reports its tracks, the master answers authoritatively.
        await env.player.sendAudioList()
        let playerReport = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        _ = try await env.master.handle(playerReport)
        let authoritativeReport = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(authoritativeReport.subType == .audioList)
        _ = try await env.player.handle(authoritativeReport)
        #expect(!playerAudio.allPlayersReported(for: audioId))

        // When: the player shares the playlist and the master adopts it.
        let audioShareData = try await playerAudio.createGameData(for: audioId)
        await env.player.game(message: audioShareData, actionType: .generic)
        let contribution = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        _ = try await env.master.handle(contribution)
        let reveal = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(reveal.type == .reveal)
        let acknowledgement = try #require(try await env.player.handle(reveal))
        #expect(acknowledgement.subType == .ok)
        _ = try await env.master.handle(acknowledgement)

        // Then: both sides know everyone has it, so the player's share button turns to play.
        #expect(env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId))
        #expect(playerAudio.allPlayersReported(for: audioId))
    }

    @Test("Master requests and imports a Character package only after a version mismatch")
    func characterJoinHandshake() async throws {
        // Given
        let env = try await PlayerMasterControllerTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.playerRoot.adventureRoot,
            name: ResourcesDebug.photoTestData,
            itemCounter: 0
        )
        env.masterRoot.adventureRoot.startGame()
        env.playerRoot.adventureRoot.startGame()

        let photoId = try #require(
            env.playerRoot.photoRoot.itemController.itemDataModel.items.first {
                env.playerRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
            }
        )
        let characterId = await env.playerRoot.characterRoot.itemController.addNew(type: .character)
        let playerCharacter = env.playerRoot.characterRoot.itemController.itemOrEmpty(for: characterId)
        playerCharacter.name = "Portrait Character"
        playerCharacter.photoId = photoId
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
        let advertisedVersion = reference.data.version
        let playerVersion = await env.playerRoot.characterRoot.gameControllable.networkVersion(for: characterId)

        // Then: a missing Character makes the master request the package.
        #expect(reference.data.data == nil)
        #expect(advertisedVersion != 0)
        #expect(advertisedVersion == playerVersion)
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

        // Then: the master imports the recursive package, including the pin photo.
        let importResponse = try await env.master.handle(package)
        #expect(importResponse == nil)
        let masterCharacter = try #require(await env.masterRoot.characterRoot.itemController.item(for: characterId))
        let importedMasterVersion = await env.masterRoot.characterRoot.gameControllable.networkVersion(for: characterId)
        #expect(masterCharacter.name == playerCharacter.name)
        #expect(env.masterRoot.photoRoot.itemController.itemDataModel.items.contains(photoId))
        #expect(importedMasterVersion == advertisedVersion)

        // And: the same metadata now needs no package request.
        let matchingResponse = try await env.master.handle(reference)
        #expect(matchingResponse == nil)
    }
}
#endif
