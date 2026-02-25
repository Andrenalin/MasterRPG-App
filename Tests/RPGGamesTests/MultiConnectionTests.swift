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

/// Test environment for multi-player game scenarios.
///
/// Provides a master controller and 3 player controllers with shared network infrastructure.
struct MultiConnectionTestEnvironment {
    let master: MasterController
    let masterRoot: GameRoot
    let masterConfig: GameConfigModel

    let player1: PlayerController
    let player1Root: GameRoot
    let player1Config: GameConfigModel

    let player2: PlayerController
    let player2Root: GameRoot
    let player2Config: GameConfigModel

    let player3: PlayerController
    let player3Root: GameRoot
    let player3Config: GameConfigModel

    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: NetworkController
    let networkProxyController: NetworkProxyController

    /// Creates a complete test environment with master + 3 players
    static func create() async throws -> MultiConnectionTestEnvironment {
        // MARK: - Network Infrastructure

        let masterDelegateSpy = MasterNetworkStoreDelegateMock()
        let playerDelegateSpy = PlayerNetworkStoreDelegateMock()
        let masterNetworkSpy = await MasterNetworkControllableMock()
        let playerNetworkSpy = await PlayerStoreAbstractionMock()

        let networkController = await NetworkController(
            name: "Hello Test",
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )
        await networkController.model.setMaster(delegate: masterDelegateSpy)
        await networkController.model.setPlayer(delegate: playerDelegateSpy)

        let networkProxyController = await NetworkProxyController(
            name: "Hello Test",
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )

        // MARK: - Master Setup

        let masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        masterRoot.networkStore = networkController
        masterRoot.networkProxyStore = networkProxyController

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin"),
            players: [],
            controls: []
        )
        await masterRoot.gameModel.reset(gameConfig: masterConfig)
        let master = await MasterController(root: masterRoot, asProxy: false)

        // MARK: - Player 1 Setup

        let player1Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player1Root.adventureRoot)
        try await MockRoot.resetGameController(for: player1Root)
        player1Root.networkStore = networkController

        let player1Id = UUID()
        let player1Config = GameConfigModel(
            id: player1Id,
            state: .started,
            master: .empty,
            players: [PlayerGameModel(id: player1Id, type: .player, name: "Player - 1")],
            controls: []
        )
        await player1Root.gameModel.reset(gameConfig: player1Config)
        let player1 = await PlayerController(root: player1Root, asGameMaster: false)

        // MARK: - Player 2 Setup

        let player2Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player2Root.adventureRoot)
        try await MockRoot.resetGameController(for: player2Root)
        player2Root.networkStore = networkController

        let player2Id = UUID()
        let player2Config = GameConfigModel(
            id: player2Id,
            state: .started,
            master: .empty,
            players: [PlayerGameModel(id: player2Id, type: .player, name: "Player - 2")],
            controls: []
        )
        await player2Root.gameModel.reset(gameConfig: player2Config)
        let player2 = await PlayerController(root: player2Root, asGameMaster: false)

        // MARK: - Player 3 Setup

        let player3Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player3Root.adventureRoot)
        try await MockRoot.resetGameController(for: player3Root)
        player3Root.networkStore = networkController

        let player3Id = UUID()
        let player3Config = GameConfigModel(
            id: player3Id,
            state: .started,
            master: .empty,
            players: [PlayerGameModel(id: player3Id, type: .player, name: "Player - 3")],
            controls: []
        )
        await player3Root.gameModel.reset(gameConfig: player3Config)
        let player3 = await PlayerController(root: player3Root, asGameMaster: false)

        return MultiConnectionTestEnvironment(
            master: master,
            masterRoot: masterRoot,
            masterConfig: masterConfig,
            player1: player1,
            player1Root: player1Root,
            player1Config: player1Config,
            player2: player2,
            player2Root: player2Root,
            player2Config: player2Config,
            player3: player3,
            player3Root: player3Root,
            player3Config: player3Config,
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController,
            networkProxyController: networkProxyController
        )
    }
}

// MARK: - Multi-Connection Audio Tests

@Suite("Multi-player audio synchronization")
struct MultiConnectionAudioTests {

    @Test("Master broadcasts audio show command to all players")
    func masterBroadcastsAudioShowToAllPlayers() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try await #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.count == 2)

        await env.masterRoot.adventureRoot.startGame()
        await env.player1Root.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = await env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        await #expect(env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)

        // Act
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)

        // Assert
        let sendedShowAudioData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(nil != sendedShowAudioData)
        #expect(sendedShowAudioData?.data.id == audioId)
        #expect(sendedShowAudioData?.data.type == .audio)
        #expect(sendedShowAudioData?.data.version == version)
    }

    @Test("Players receive and acknowledge audio show command")
    func playersReceiveAndAcknowledgeAudioShow() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()
        await env.player1Root.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        // Act - Player 1 receives show command
        await env.player1.receivedProcess(showCommand!)

        // Assert - Player 1 acknowledges
        let player1Response = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(player1Response?.subType == .show)
        await #expect(env.player1Root.audioRoot.gameController.currentId != audioId)
        await #expect(env.player1Root.gameModel.gameConfig.master == env.masterConfig.master)
        await #expect(env.player1Root.gameModel.gameConfig.players == env.player1Config.players)
    }

    @Test("All three players independently acknowledge audio show")
    func allThreePlayersAcknowledgeAudioShow() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        // Act - All players receive and process
        await env.player1.receivedProcess(showCommand!)
        let response1 = env.playerNetworkSpy.requestData as? GameNetworkModel

        await env.player2.receivedProcess(showCommand!)
        let response2 = env.playerNetworkSpy.requestData as? GameNetworkModel

        await env.player3.receivedProcess(showCommand!)
        let response3 = env.playerNetworkSpy.requestData as? GameNetworkModel

        // Assert - All three acknowledged
        #expect(response1?.subType == .show)
        #expect(response2?.subType == .show)
        #expect(response3?.subType == .show)

        await #expect(env.player1Root.audioRoot.gameController.currentId != audioId)
        await #expect(env.player2Root.audioRoot.gameController.currentId != audioId)
        await #expect(env.player3Root.audioRoot.gameController.currentId != audioId)
    }

    @Test("Master aggregates player acknowledgments and broadcasts audio data")
    func masterAggregatesAcknowledgmentsAndBroadcastsData() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = await env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        await env.player1.receivedProcess(showCommand!)
        let response1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        try #require(response1 != nil)

        await env.player3.receivedProcess(showCommand!)
        let response3 = env.playerNetworkSpy.requestData as? GameNetworkModel
        try #require(response3 != nil)

        // Act - Master receives first acknowledgment
        await env.master.receivedProcess(response1!, connectionId: nil)

        // Assert - Master broadcasts audio data
        let audioData1 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(audioData1?.data.id == audioId)
        #expect(audioData1?.data.type == .audio)
        #expect(audioData1?.data.version == version)
        await #expect(env.masterRoot.gameModel.gameConfig.controls == [
            SharingControlModel(id: env.player1Config.id, name: env.player1Config.name, show: true)
        ])

        // Act - Master receives third player acknowledgment
        await env.master.receivedProcess(response3!, connectionId: nil)

        // Assert - Master updates controls
        let audioData3 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(audioData3?.data.id == audioId)
        await #expect(env.masterRoot.gameModel.gameConfig.controls == [
            SharingControlModel(id: env.player1Config.id, name: env.player1Config.name, show: true),
            SharingControlModel(id: env.player3Config.id, name: env.player3Config.name, show: true)
        ])
    }

    @Test("Players receive audio data and confirm receipt")
    func playersReceiveAudioDataAndConfirm() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = await env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        await env.player1.receivedProcess(showCommand!)
        let response1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        try #require(response1 != nil)

        await env.master.receivedProcess(response1!, connectionId: nil)
        let audioData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(audioData != nil)

        // Act - Player 1 processes audio data
        await env.player1.receivedProcess(audioData!)

        // Assert - Player 1 confirms with OK
        let confirmResponse = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(confirmResponse?.subType == .ok)
        await #expect(env.player1Root.audioRoot.gameController.currentId == audioId)
        await #expect(env.player1Root.audioRoot.gameController.gameItem(for: audioId).version == version)
        await #expect(env.player1Root.audioRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test("Master detects all players reported after receiving all confirmations")
    func masterDetectsAllPlayersReported() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        // All players acknowledge show
        await env.player1.receivedProcess(showCommand!)
        let ack1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player2.receivedProcess(showCommand!)
        let ack2 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player3.receivedProcess(showCommand!)
        let ack3 = env.playerNetworkSpy.requestData as? GameNetworkModel

        // Master sends audio data
        await env.master.receivedProcess(ack1!, connectionId: nil)
        let audioData1 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.master.receivedProcess(ack2!, connectionId: nil)
        let audioData2 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.master.receivedProcess(ack3!, connectionId: nil)
        let audioData3 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel

        // Players process audio
        await env.player1.receivedProcess(audioData1!)
        let ok1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player2.receivedProcess(audioData2!)
        let ok2 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player3.receivedProcess(audioData3!)
        let ok3 = env.playerNetworkSpy.requestData as? GameNetworkModel

        // Act - Master receives confirmations
        await env.master.receivedProcess(ok3!, connectionId: nil)
        var allReported = await env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == false) // Not all yet

        await env.master.receivedProcess(ok2!, connectionId: nil)
        allReported = await env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == false) // Still not all

        await env.master.receivedProcess(ok1!, connectionId: nil)

        // Assert - All players reported
        allReported = await env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == true)

        await #expect(env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted() == [
            env.player1Config.id,
            env.player2Config.id,
            env.player3Config.id,
            env.masterConfig.id
        ].sorted())
    }

    @Test("Master broadcasts play command after all players report")
    func masterBroadcastsPlayCommandAfterAllReport() async throws {
        // Arrange - Complete audio distribution flow
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

        // Complete show/acknowledge/data/confirm cycle (abbreviated for brevity)
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        await env.player1.receivedProcess(showCommand!)
        let ack1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.master.receivedProcess(ack1!, connectionId: nil)
        let audioData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.player1.receivedProcess(audioData!)
        let ok1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.master.receivedProcess(ok1!, connectionId: nil)

        // Act - Master sends play command
        let playData = await env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
        await env.master.game(message: playData, actionType: .playAudio)

        // Assert - Play command broadcast
        let playCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(playCommand != nil)
    }

    @Test("Players receive play command and start audio playback")
    func playersReceivePlayCommandAndStartPlayback() async throws {
        // Arrange - Setup and distribute audio
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

        // Complete show/data cycle
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        await env.player1.receivedProcess(showCommand!)
        let ack1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.master.receivedProcess(ack1!, connectionId: nil)
        let audioData = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.player1.receivedProcess(audioData!)
        let ok1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.master.receivedProcess(ok1!, connectionId: nil)

        // Master sends play
        let playData = await env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
        await env.master.game(message: playData, actionType: .playAudio)
        let playCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(playCommand != nil)

        env.playerNetworkSpy.requestData = nil

        // Act - Player receives play command
        await env.player1.receivedProcess(playCommand!)

        // Assert - Player starts playback, no response expected
        let noResponse = env.playerNetworkSpy.requestData
        #expect(noResponse == nil)
        await #expect(env.player1Root.audioRoot.audioController.model.playList.count == 1)
        await #expect(env.player1Root.audioRoot.audioController.model.playList[0].id == audioId)
        await #expect(env.player1Root.audioRoot.audioController.model.currentId == audioId)
    }

    @Test("All three players start synchronized audio playback")
    func allThreePlayersStartSynchronizedPlayback() async throws {
        // Arrange - Complete setup through play command
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        await env.masterRoot.adventureRoot.startGame()

        let audioId = await env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

        // Complete distribution to all players (abbreviated)
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        // All players get audio data
        await env.player1.receivedProcess(showCommand!)
        let ack1 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player2.receivedProcess(showCommand!)
        let ack2 = env.playerNetworkSpy.requestData as? GameNetworkModel
        await env.player3.receivedProcess(showCommand!)
        let ack3 = env.playerNetworkSpy.requestData as? GameNetworkModel

        await env.master.receivedProcess(ack1!, connectionId: nil)
        let data1 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.master.receivedProcess(ack2!, connectionId: nil)
        let data2 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        await env.master.receivedProcess(ack3!, connectionId: nil)
        let data3 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel

        await env.player1.receivedProcess(data1!)
        await env.player2.receivedProcess(data2!)
        await env.player3.receivedProcess(data3!)

        // Master sends play
        let playData = await env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
        await env.master.game(message: playData, actionType: .playAudio)
        let playCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(playCommand != nil)

        // Act - All players receive play command
        await env.player1.receivedProcess(playCommand!)
        await env.player2.receivedProcess(playCommand!)
        await env.player3.receivedProcess(playCommand!)

        // Assert - All three players playing
        await #expect(env.player1Root.audioRoot.audioController.model.currentId == audioId)
        await #expect(env.player2Root.audioRoot.audioController.model.currentId == audioId)
        await #expect(env.player3Root.audioRoot.audioController.model.currentId == audioId)

        await #expect(env.player1Root.audioRoot.audioController.model.playList.count == 1)
        await #expect(env.player2Root.audioRoot.audioController.model.playList.count == 1)
        await #expect(env.player3Root.audioRoot.audioController.model.playList.count == 1)

        // All players have complete player list
        let expectedPlayers = [
            env.player1Config.id,
            env.player2Config.id,
            env.player3Config.id,
            env.masterConfig.id
        ].sorted()

        let player1Players = await env.player1Root.audioRoot.itemController.itemSync(for: audioId, noGame: true)!.players.sorted()
        let player2Players = await env.player2Root.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted()
        let player3Players = await env.player3Root.audioRoot.itemController.itemOrEmpty(for: audioId).players.sorted()

        #expect(player1Players == expectedPlayers)
        #expect(player2Players == expectedPlayers)
        #expect(player3Players == expectedPlayers)
    }
}

#endif
