// @copyright André Trettin

@testable import CoreRPG
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
@MainActor
struct MultiConnectionTestEnvironment {
    let master: MasterController
    let masterRoot: GameRoot
    let masterConfig: GameConfigModel
    let masterRoster: GameRosterModel

    let player1: PlayerController
    let player1Root: GameRoot
    let player1Config: GameConfigModel
    let player1Roster: GameRosterModel

    let player2: PlayerController
    let player2Root: GameRoot
    let player2Config: GameConfigModel
    let player2Roster: GameRosterModel

    let player3: PlayerController
    let player3Root: GameRoot
    let player3Config: GameConfigModel
    let player3Roster: GameRosterModel

    let masterDelegateSpy: MasterNetworkStoreDelegateMock
    let playerDelegateSpy: PlayerNetworkStoreDelegateMock
    let masterNetworkSpy: MasterNetworkControllableMock
    let playerNetworkSpy: PlayerStoreAbstractionMock
    let networkController: GameNetworkController
    let networkProxyController: GameNetworkController

    /// Creates a complete test environment with master + 3 players
    static func create() async throws -> MultiConnectionTestEnvironment {
        // MARK: - Network Infrastructure

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

        let networkProxyController = GameNetworkController(
            name: "Hello Test",
            proxy: true,
            masterBuilder: { _, _ in masterNetworkSpy },
            playerBuilder: { _, _ in playerNetworkSpy }
        )

        // MARK: - Master Setup

        let masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        await MainActor.run {
            masterRoot.networkStore = networkController
            masterRoot.networkProxyStore = networkProxyController
        }

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin")
        )
        let masterRoster = GameRosterModel()
        masterRoot.gameModel.reset(gameConfig: masterConfig, gameRoster: masterRoster)
        let master = MasterController(root: masterRoot, asProxy: false)

        // MARK: - Player 1 Setup

        let player1Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player1Root.adventureRoot)
        try await MockRoot.resetGameController(for: player1Root)
        await MainActor.run {
            player1Root.networkStore = networkController
        }

        let player1Id = UUID()
        let player1Config = GameConfigModel(id: player1Id, state: .started, master: .empty)
        let player1Roster = GameRosterModel(players: [PlayerGameModel(id: player1Id, type: .player, name: "Player - 1")])
        player1Root.gameModel.reset(gameConfig: player1Config, gameRoster: player1Roster)
        let player1 = PlayerController(root: player1Root, asGameMaster: false)

        // MARK: - Player 2 Setup

        let player2Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player2Root.adventureRoot)
        try await MockRoot.resetGameController(for: player2Root)
        await MainActor.run {
            player2Root.networkStore = networkController
        }

        let player2Id = UUID()
        let player2Config = GameConfigModel(id: player2Id, state: .started, master: .empty)
        let player2Roster = GameRosterModel(players: [PlayerGameModel(id: player2Id, type: .player, name: "Player - 2")])
        player2Root.gameModel.reset(gameConfig: player2Config, gameRoster: player2Roster)
        let player2 = PlayerController(root: player2Root, asGameMaster: false)

        // MARK: - Player 3 Setup

        let player3Root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: player3Root.adventureRoot)
        try await MockRoot.resetGameController(for: player3Root)
        await MainActor.run {
            player3Root.networkStore = networkController
        }

        let player3Id = UUID()
        let player3Config = GameConfigModel(id: player3Id, state: .started, master: .empty)
        let player3Roster = GameRosterModel(players: [PlayerGameModel(id: player3Id, type: .player, name: "Player - 3")])
        player3Root.gameModel.reset(gameConfig: player3Config, gameRoster: player3Roster)
        let player3 = PlayerController(root: player3Root, asGameMaster: false)

        return MultiConnectionTestEnvironment(
            master: master,
            masterRoot: masterRoot,
            masterConfig: masterConfig,
            masterRoster: masterRoster,
            player1: player1,
            player1Root: player1Root,
            player1Config: player1Config,
            player1Roster: player1Roster,
            player2: player2,
            player2Root: player2Root,
            player2Config: player2Config,
            player2Roster: player2Roster,
            player3: player3,
            player3Root: player3Root,
            player3Config: player3Config,
            player3Roster: player3Roster,
            masterDelegateSpy: masterDelegateSpy,
            playerDelegateSpy: playerDelegateSpy,
            masterNetworkSpy: masterNetworkSpy,
            playerNetworkSpy: playerNetworkSpy,
            networkController: networkController,
            networkProxyController: networkProxyController
        )
    }
}

enum MultiplayerPhotoRole: CaseIterable, Hashable, Sendable {
    case player1
    case player2
    case player3
    case player4
    case observer1
    case observer2
    case proxy1
    case proxy2

    var name: String {
        switch self {
        case .player1: "Player - 1"
        case .player2: "Player - 2"
        case .player3: "Player - 3"
        case .player4: "Player - 4"
        case .observer1: "Observer - 1"
        case .observer2: "Observer - 2"
        case .proxy1: "Proxy - 1"
        case .proxy2: "Proxy - 2"
        }
    }

    var type: GameType {
        switch self {
        case .player1, .player2, .player3, .player4:
            .player
        case .observer1, .observer2:
            .observer
        case .proxy1, .proxy2:
            .proxy
        }
    }

    var proxyHost: MultiplayerPhotoRole? {
        switch self {
        case .proxy1:
            .player1
        case .proxy2:
            .player3
        default:
            nil
        }
    }
}

struct MultiplayerPhotoScenario: CustomStringConvertible, Sendable {
    let name: String
    let missingRoles: Set<MultiplayerPhotoRole>

    var description: String { name }
    var missingRolesInTopologyOrder: [MultiplayerPhotoRole] {
        MultiplayerPhotoRole.allCases.filter { missingRoles.contains($0) }
    }

    static let all: [MultiplayerPhotoScenario] = [
        MultiplayerPhotoScenario(
            name: "all devices already have the photo",
            missingRoles: []
        ),
        MultiplayerPhotoScenario(
            name: "one player is missing the photo",
            missingRoles: [.player1]
        ),
        MultiplayerPhotoScenario(
            name: "one player, one observer, and one proxy are missing the photo",
            missingRoles: [.player2, .observer1, .proxy1]
        ),
        MultiplayerPhotoScenario(
            name: "no receiver has the photo",
            missingRoles: Set(MultiplayerPhotoRole.allCases)
        )
    ]
}

@MainActor
private struct MultiplayerPhotoNetworkHarness {
    let directMasterSpy: MasterNetworkControllableMock
    let directPlayerSpy: PlayerStoreAbstractionMock
    let proxyMasterSpy: MasterNetworkControllableMock
    let proxyPlayerSpy: PlayerStoreAbstractionMock
    let directNetwork: GameNetworkController
    let proxyNetwork: GameNetworkController

    static func make(name: String) -> MultiplayerPhotoNetworkHarness {
        let directMasterSpy = MasterNetworkControllableMock()
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyMasterSpy = MasterNetworkControllableMock()
        let proxyPlayerSpy = PlayerStoreAbstractionMock()

        let directNetwork = GameNetworkController(
            name: name,
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        let proxyNetwork = GameNetworkController(
            name: "\(name) Proxy",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in proxyPlayerSpy }
        )

        return MultiplayerPhotoNetworkHarness(
            directMasterSpy: directMasterSpy,
            directPlayerSpy: directPlayerSpy,
            proxyMasterSpy: proxyMasterSpy,
            proxyPlayerSpy: proxyPlayerSpy,
            directNetwork: directNetwork,
            proxyNetwork: proxyNetwork
        )
    }
}

@MainActor
private struct MultiplayerPhotoParticipant {
    let role: MultiplayerPhotoRole
    let root: GameRoot
    let controller: PlayerController
    let config: GameConfigModel
    let playerModel: PlayerGameModel
    let network: MultiplayerPhotoNetworkHarness

    func receive(_ model: GameNetworkModel) async throws -> GameNetworkModel {
        network.directPlayerSpy.requestData = nil
        network.proxyPlayerSpy.requestData = nil

        if role.type == .proxy {
            await controller.receivedProxy(model)
            return try #require(network.proxyPlayerSpy.requestData as? GameNetworkModel)
        }

        await controller.receivedProcess(model)
        return try #require(network.directPlayerSpy.requestData as? GameNetworkModel)
    }

    /// Delivers a message that this participant must ignore (targeted at
    /// someone else) — asserts no response was sent.
    func receiveIgnored(_ model: GameNetworkModel) async -> Bool {
        network.directPlayerSpy.requestData = nil
        network.proxyPlayerSpy.requestData = nil

        if role.type == .proxy {
            await controller.receivedProxy(model)
            return network.proxyPlayerSpy.requestData == nil
        }

        await controller.receivedProcess(model)
        return network.directPlayerSpy.requestData == nil
    }
}

@MainActor
private struct MultiplayerPhotoTopology {
    let master: MasterController
    let masterRoot: GameRoot
    let masterConfig: GameConfigModel
    let masterNetwork: MultiplayerPhotoNetworkHarness
    let participants: [MultiplayerPhotoParticipant]

    var participantIds: [UUID] {
        participants.map(\.config.id)
    }

    static func make() async throws -> MultiplayerPhotoTopology {
        let masterNetwork = MultiplayerPhotoNetworkHarness.make(name: "Master")
        let masterRoot = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: masterRoot.adventureRoot)
        try await MockRoot.resetGameController(for: masterRoot)
        masterRoot.networkStore = masterNetwork.directNetwork
        masterRoot.networkProxyStore = masterNetwork.proxyNetwork

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin")
        )

        var participants: [MultiplayerPhotoParticipant] = []
        for role in MultiplayerPhotoRole.allCases {
            let network = MultiplayerPhotoNetworkHarness.make(name: role.name)
            let root = try await MockRoot.createGameRoot()
            try await MockRoot.resetTestData(for: root.adventureRoot)
            try await MockRoot.resetGameController(for: root)
            root.networkStore = network.directNetwork
            root.networkProxyStore = network.proxyNetwork

            let id = UUID()
            let config = GameConfigModel(id: id, state: .started, master: .empty)
            let playerModel = PlayerGameModel(id: id, type: role.type, name: role.name)
            root.gameModel.reset(gameConfig: config, gameRoster: GameRosterModel(players: [playerModel]))

            let controller = PlayerController(root: root, asGameMaster: false)
            participants.append(MultiplayerPhotoParticipant(
                role: role,
                root: root,
                controller: controller,
                config: config,
                playerModel: playerModel,
                network: network
            ))
        }

        let roster = GameRosterModel(players: participants.map(\.playerModel))
        let controls = participants.map { SharingControlModel(id: $0.config.id, name: $0.role.name, show: true) }
        masterRoot.gameModel.reset(
            gameConfig: masterConfig,
            gameRoster: roster,
            gameControl: GameControlModel(controls: controls)
        )

        let master = MasterController(root: masterRoot, asProxy: false)
        return MultiplayerPhotoTopology(
            master: master,
            masterRoot: masterRoot,
            masterConfig: masterConfig,
            masterNetwork: masterNetwork,
            participants: participants
        )
    }

    func importPhotoData() async throws -> UUID {
        try await MockRoot.importTestData(into: masterRoot.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        for participant in participants {
            try await MockRoot.importTestData(into: participant.root.adventureRoot, name: ResourcesDebug.photoTestData, itemCounter: 0)
        }

        masterRoot.adventureRoot.startGame()
        for participant in participants {
            participant.root.adventureRoot.startGame()
        }

        return try #require(masterRoot.photoRoot.itemController.itemDataModel.items.first {
            masterRoot.photoRoot.itemController.itemSync(for: $0)?.fileUrl != nil
        })
    }

    func removePhoto(_ photoId: UUID, from missingRoles: Set<MultiplayerPhotoRole>) {
        for participant in participants where missingRoles.contains(participant.role) {
            participant.root.photoRoot.itemController.itemDataModel.resetModel(id: photoId)
            participant.root.photoRoot.gameController.gameModel.itemData[photoId] = nil
            participant.root.photoRoot.gameController.gameModel.items.removeAll { $0 == photoId }
        }
    }

    func participant(for role: MultiplayerPhotoRole) throws -> MultiplayerPhotoParticipant {
        try #require(participants.first { $0.role == role })
    }
}

// MARK: - Multi-Connection Audio Tests

@Suite("Multi-player audio synchronization")
@MainActor
struct MultiConnectionAudioTests {

    @Test("Initial and reconnect audio reports are rebroadcast authoritatively")
    func initialAndReconnectAudioReportsAreRebroadcast() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 3
        )
        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

        func audioReport(from root: GameRoot, availableIds: [UUID]) -> GameNetworkModel {
            let request = AudioListRequest(list: availableIds, players: [:])
            let data = NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: request.encodeData())
            return root.gameModel.outgoingMessage(
                counter: 0,
                type: .update,
                subType: .audioList,
                asMaster: false,
                data: data
            )
        }

        // Act - Player 1 reports its initial availability.
        _ = try await env.master.handle(audioReport(from: env.player1Root, availableIds: [audioId]))
        let firstUpdate = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        _ = try await env.player2.handle(firstUpdate)

        // Assert - The master rebroadcast reaches another local player.
        #expect(firstUpdate.subType == .audioList)
        #expect(env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(env.player2Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))

        // Act - Player 2 reports and the next authoritative update reaches Player 1.
        _ = try await env.master.handle(audioReport(from: env.player2Root, availableIds: [audioId]))
        let secondUpdate = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        _ = try await env.player1.handle(secondUpdate)

        // Assert
        #expect(secondUpdate.subType == .audioList)
        #expect(env.player1Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(env.player1Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player2Config.id))

        // Act - Player 1 reconnects without the audio and replaces its old report.
        _ = try await env.master.handle(audioReport(from: env.player1Root, availableIds: []))
        let reconnectUpdate = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        _ = try await env.player2.handle(reconnectUpdate)

        // Assert - Stale Player 1 availability is removed everywhere; Player 2 remains.
        #expect(reconnectUpdate.subType == .audioList)
        #expect(!env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player2Config.id))
        #expect(!env.player2Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(env.player2Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player2Config.id))
        #expect(env.masterNetworkSpy.calledSendResponseAll == 3)
    }

    @Test("Audio receipt waits for local bytes and propagates after storage")
    func audioReceiptWaitsForLocalBytesAndPropagates() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 3
        )

        env.masterRoot.adventureRoot.startGame()
        env.player1Root.adventureRoot.startGame()
        env.player2Root.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let sourceAudio = env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId)
        let sourceFile = try #require(sourceAudio.fileUrl)
        let missingFile = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).m4a"),
            location: .local,
            module: NetworkModules.audio.token,
            relativeUrl: nil,
            contentHash: sourceFile.contentHash
        )
        let metadataOnlyAudio = AudioModel(
            id: audioId,
            name: sourceAudio.name,
            description: sourceAudio.description,
            tags: sourceAudio.tags,
            category: sourceAudio.category,
            displayState: sourceAudio.displayState,
            fileUrl: missingFile,
            entries: sourceAudio.entries,
            parentId: sourceAudio.parentId
        )
        env.player1Root.audioRoot.itemController.replace(model: metadataOnlyAudio, isInsert: true)

        let audioReference = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        #expect(metadataOnlyAudio.version == audioReference.version)
        #expect(await !env.player1Root.audioRoot.gameController.hasLocalAudioData(for: audioId))

        await env.master.show(for: audioReference)
        let reveal = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)

        // Act - Metadata alone must result in a data request, not an OK report.
        let request = try #require(try await env.player1.handle(reveal))

        // Assert
        #expect(request.subType == .show)
        #expect(!env.player1Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(!env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))

        // Act - The master answers the request; only the successful import is acknowledged.
        let audioData = try #require(try await env.master.handle(request))
        await env.master.send(
            type: request.type,
            subtype: request.subType,
            updated: audioData,
            playerId: env.player1Config.id
        )
        let targetedAudio = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        let acknowledgment = try #require(try await env.player1.handle(targetedAudio))

        // Assert - The bytes exist before OK is emitted.
        #expect(acknowledgment.subType == .ok)
        #expect(await env.player1Root.audioRoot.gameController.hasLocalAudioData(for: audioId))

        // Act - The master publishes the authoritative report to another local player.
        _ = try await env.master.handle(acknowledgment)
        let reportUpdate = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        #expect(reportUpdate.subType == .audioList)
        _ = try await env.player2.handle(reportUpdate)

        // Assert
        #expect(env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(env.player2Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
    }

    @Test("Master does not report a failed audio receipt")
    func masterDoesNotReportFailedAudioReceipt() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 3
        )
        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let audioReference = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        let failedReceipt = env.player1Root.gameModel.outgoingMessage(
            counter: 0,
            type: .reveal,
            subType: .failed,
            asMaster: false,
            data: audioReference
        )

        // Act
        _ = try await env.master.handle(failedReceipt)
        _ = try await env.player2.handle(failedReceipt)

        // Assert
        #expect(!env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
        #expect(!env.player2Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.player1Config.id))
    }

    @Test("Master broadcasts audio show command to all players")
    func masterBroadcastsAudioShowToAllPlayers() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)
        try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.count == 2)

        env.masterRoot.adventureRoot.startGame()
        env.player1Root.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
        #expect(env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).entries.isEmpty)

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

        env.masterRoot.adventureRoot.startGame()
        env.player1Root.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let audioShareData = await env.masterRoot.audioRoot.gameController.share(id: audioId)
        await env.master.show(for: audioShareData)
        let showCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(showCommand != nil)

        // Act - Player 1 receives show command
        await env.player1.receivedProcess(showCommand!)

        // Assert - Player 1 acknowledges
        let player1Response = env.playerNetworkSpy.requestData as? GameNetworkModel
        #expect(player1Response?.subType == .show)
        #expect(await env.player1Root.audioRoot.gameController.currentId != audioId)
        #expect(env.player1Root.gameModel.gameConfig.master == env.masterConfig.master)
        #expect(env.player1Root.gameModel.gameRoster.players == env.player1Roster.players)
    }

    @Test("All three players independently acknowledge audio show")
    func allThreePlayersAcknowledgeAudioShow() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
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

        #expect(await env.player1Root.audioRoot.gameController.currentId != audioId)
        #expect(await env.player2Root.audioRoot.gameController.currentId != audioId)
        #expect(await env.player3Root.audioRoot.gameController.currentId != audioId)
    }

    @Test("Master aggregates player acknowledgments and broadcasts audio data")
    func masterAggregatesAcknowledgmentsAndBroadcastsData() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
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
        #expect(env.masterRoot.gameModel.gameControl.controls == [
            SharingControlModel(id: env.player1Config.id, name: env.player1Roster.players[0].name, show: true)
        ])

        // Act - Master receives third player acknowledgment
        await env.master.receivedProcess(response3!, connectionId: nil)

        // Assert - Master updates controls
        let audioData3 = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        #expect(audioData3?.data.id == audioId)
        #expect(env.masterRoot.gameModel.gameControl.controls == [
            SharingControlModel(id: env.player1Config.id, name: env.player1Roster.players[0].name, show: true),
            SharingControlModel(id: env.player3Config.id, name: env.player3Roster.players[0].name, show: true)
        ])
    }

    @Test("Players receive audio data and confirm receipt")
    func playersReceiveAudioDataAndConfirm() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
        let version = env.masterRoot.audioRoot.itemController.itemOrEmpty(for: audioId).version
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
        #expect(await env.player1Root.audioRoot.gameController.currentId == audioId)
        #expect(env.player1Root.audioRoot.gameController.gameItem(for: audioId).version == version)
        #expect(env.player1Root.audioRoot.itemController.itemDataModel.items.count == 1)
    }

    @Test("Master detects all players reported after receiving all confirmations")
    func masterDetectsAllPlayersReported() async throws {
        // Arrange
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]
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
        var allReported = env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == false) // Not all yet

        await env.master.receivedProcess(ok2!, connectionId: nil)
        allReported = env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == false) // Still not all

        await env.master.receivedProcess(ok1!, connectionId: nil)

        // Assert - All players reported
        allReported = env.masterRoot.audioRoot.gameController.allPlayersReported(for: audioId)
        #expect(allReported == true)

        #expect(env.masterRoot.audioRoot.gameController.gameModel.playerReport(for: audioId).sorted() == [
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

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

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
        let playData = env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
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

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

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
        let playData = env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
        await env.master.game(message: playData, actionType: .playAudio)
        let playCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(playCommand != nil)

        env.playerNetworkSpy.requestData = nil

        // Act - Player receives play command
        await env.player1.receivedProcess(playCommand!)

        // Assert - Player starts playback, no response expected
        let noResponse = env.playerNetworkSpy.requestData
        #expect(noResponse == nil)
        try #require(env.player1Root.audioRoot.audioController.model.playList.count == 1)
        #expect(env.player1Root.audioRoot.audioController.model.playList[0].id == audioId)
        #expect(env.player1Root.audioRoot.audioController.model.currentId == audioId)
    }

    @Test("All three players start synchronized audio playback")
    func allThreePlayersStartSynchronizedPlayback() async throws {
        // Arrange - Complete setup through play command
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot, name: ResourcesDebug.audioTestData, itemCounter: 3)

        env.masterRoot.adventureRoot.startGame()

        let audioId = env.masterRoot.audioRoot.itemController.itemDataModel.items[1]

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
        let playData = env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)
        await env.master.game(message: playData, actionType: .playAudio)
        let playCommand = env.masterNetworkSpy.sendResponseData as? GameNetworkModel
        try #require(playCommand != nil)

        // Act - All players receive play command
        await env.player1.receivedProcess(playCommand!)
        await env.player2.receivedProcess(playCommand!)
        await env.player3.receivedProcess(playCommand!)

        // Assert - All three players playing
        #expect(env.player1Root.audioRoot.audioController.model.currentId == audioId)
        #expect(env.player2Root.audioRoot.audioController.model.currentId == audioId)
        #expect(env.player3Root.audioRoot.audioController.model.currentId == audioId)

        #expect(env.player1Root.audioRoot.audioController.model.playList.count == 1)
        #expect(env.player2Root.audioRoot.audioController.model.playList.count == 1)
        #expect(env.player3Root.audioRoot.audioController.model.playList.count == 1)

    }
}

// MARK: - Multi-Connection Photo Tests

@Suite("Multi-player photo synchronization")
@MainActor
struct MultiConnectionPhotoTests {

    @Test("Master sends photo to players, observers, and proxies", arguments: MultiplayerPhotoScenario.all)
    func masterSendsPhotoToPlayersObserversAndProxies(testCase: MultiplayerPhotoScenario) async throws {
        let env = try await MultiplayerPhotoTopology.make()
        let photoId = try await env.importPhotoData()
        let version = env.masterRoot.photoRoot.itemController.itemOrEmpty(for: photoId).version
        env.removePhoto(photoId, from: testCase.missingRoles)

        let photoShareData = await env.masterRoot.photoRoot.gameController.share(id: photoId)
        await env.master.show(for: photoShareData)

        let showCommand = try #require(env.masterNetwork.directMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(showCommand.type == .reveal)
        #expect(showCommand.subType == .show)
        #expect(showCommand.data.id == photoId)
        #expect(showCommand.data.type == .photo)
        #expect(showCommand.data.data == nil)

        var initialResponses: [MultiplayerPhotoRole: GameNetworkModel] = [:]
        for participant in env.participants {
            let response = try await participant.receive(showCommand)
            initialResponses[participant.role] = response
            #expect(response.data.id == photoId)
            #expect(response.data.type == .photo)

            if testCase.missingRoles.contains(participant.role) {
                #expect(response.subType == .show)
            } else {
                #expect(response.subType == .ok)
            }
        }

        for response in initialResponses.values where response.subType == .ok {
            await env.master.receivedProcess(response, connectionId: nil)
        }

        let proxyHosts = try [MultiplayerPhotoRole.proxy1, .proxy2].map { try #require($0.proxyHost) }
        #expect(Set(proxyHosts).count == 2)
        for proxyHost in proxyHosts {
            let host = try env.participant(for: proxyHost)
            #expect(host.network.proxyMasterSpy.calledSendResponseAll > 0)
        }

        var fullDataResponses: [GameNetworkModel] = []
        for role in testCase.missingRolesInTopologyOrder {
            let missingResponse = try #require(initialResponses[role])
            await env.master.receivedProcess(missingResponse, connectionId: nil)
            let fullData = try #require(env.masterNetwork.directMasterSpy.sendResponseData as? GameNetworkModel)
            #expect(fullData.type == .reveal)
            #expect(fullData.subType == .show)
            #expect(fullData.data.id == photoId)
            #expect(fullData.data.type == .photo)
            #expect(fullData.data.version == version)
            #expect(fullData.data.data != nil)
            fullDataResponses.append(fullData)
        }

        #expect(fullDataResponses.count == testCase.missingRoles.count)

        for fullData in fullDataResponses {
            // The full payload is targeted at the requester: only the addressee
            // imports and acknowledges it, everyone else ignores it — screens of
            // participants that already show the photo no longer flip.
            let targetId = try #require(fullData.targetId)
            let addressee = try #require(env.participants.first { $0.config.id == targetId })
            let response = try await addressee.receive(fullData)
            #expect(response.subType == .ok)
            await env.master.receivedProcess(response, connectionId: nil)

            for participant in env.participants where participant.config.id != targetId {
                #expect(await participant.receiveIgnored(fullData))
            }
        }

        let reports = env.masterRoot.photoRoot.gameController.gameModel.playerReport(for: photoId)
        #expect(reports.sorted() == env.participantIds.sorted())

        for participant in env.participants {
            #expect(await participant.root.photoRoot.gameController.currentId == photoId)
            let storedPhoto = try #require(participant.root.photoRoot.itemController.itemSync(for: photoId, noGame: true))
            #expect(storedPhoto.version == version)
            #expect(storedPhoto.fileUrl != nil)
        }

        for proxyRole in [MultiplayerPhotoRole.proxy1, .proxy2] {
            let proxy = try env.participant(for: proxyRole)
            #expect(proxy.network.proxyPlayerSpy.calledRequest > 0)
        }
    }
}
