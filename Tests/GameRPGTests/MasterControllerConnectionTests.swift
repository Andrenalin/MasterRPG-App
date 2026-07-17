// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import WeatherRPG

// MARK: - MasterControllerModel unit tests

@Suite("MasterControllerModel connection mapping")
@MainActor
struct MasterControllerModelConnectionTests {

    @Test("add registers a new connectionId for a player")
    func addRegistersNewPlayer() async {
        let model = MasterControllerModel()
        let connId = UUID()
        let playerId = UUID()

        await MainActor.run { model.add(connectionId: connId, playerId: playerId) }

        let registered = await MainActor.run { model.connectIDPlayers[connId] }
        #expect(registered == playerId)
    }

    @Test("add evicts the stale connectionId when the same player reconnects")
    func addEvictsStaleConnectionOnReconnect() async {
        let model = MasterControllerModel()
        let oldConnId = UUID()
        let newConnId = UUID()
        let playerId = UUID()

        await MainActor.run { model.add(connectionId: oldConnId, playerId: playerId) }
        await MainActor.run { model.add(connectionId: newConnId, playerId: playerId) }

        let oldEntry = await MainActor.run { model.connectIDPlayers[oldConnId] }
        let newEntry = await MainActor.run { model.connectIDPlayers[newConnId] }
        #expect(oldEntry == nil, "old connectionId must be evicted when the same player reconnects")
        #expect(newEntry == playerId)
    }

    @Test("add preserves unrelated players when one player reconnects")
    func addPreservesOtherPlayersOnReconnect() async {
        let model = MasterControllerModel()
        let connA = UUID(); let playerA = UUID()
        let connBOld = UUID(); let connBNew = UUID(); let playerB = UUID()

        await MainActor.run {
            model.add(connectionId: connA, playerId: playerA)
            model.add(connectionId: connBOld, playerId: playerB)
            model.add(connectionId: connBNew, playerId: playerB)
        }

        let aEntry = await MainActor.run { model.connectIDPlayers[connA] }
        let bOldEntry = await MainActor.run { model.connectIDPlayers[connBOld] }
        let bNewEntry = await MainActor.run { model.connectIDPlayers[connBNew] }
        #expect(aEntry == playerA, "unrelated player's mapping must be untouched")
        #expect(bOldEntry == nil, "old connectionId for reconnecting player must be evicted")
        #expect(bNewEntry == playerB)
    }
}

// MARK: - GameMessagePipeline unit tests

@Suite("GameMessagePipeline")
struct GameMessagePipelineTests {

    @Test("duplicate non-ack message is ignored")
    func duplicateNonAckMessageIsIgnored() async {
        let pipeline = GameMessagePipeline()
        let message = Self.message(counter: 4, senderId: UUID())
        let event = GameMessageEvent(model: message, origin: .direct(UUID()))

        let first = await pipeline.enqueue(event)
        let duplicate = await pipeline.enqueue(GameMessageEvent(model: message, origin: .sharePlay(UUID())))

        #expect(first)
        #expect(!duplicate)
    }

    @Test("same counter from different senders is accepted")
    func sameCounterFromDifferentSendersIsAccepted() async {
        let pipeline = GameMessagePipeline()
        let first = Self.message(counter: 8, senderId: UUID())
        let second = Self.message(counter: 8, senderId: UUID(), dataId: first.data.id)

        let firstQueued = await pipeline.enqueue(GameMessageEvent(model: first, origin: .direct(UUID())))
        let secondQueued = await pipeline.enqueue(GameMessageEvent(model: second, origin: .direct(UUID())))

        #expect(firstQueued)
        #expect(secondQueued)
    }

    @Test("counter zero messages are not deduplicated")
    func counterZeroMessagesAreNotDeduplicated() async {
        let pipeline = GameMessagePipeline()
        let message = Self.message(counter: 0, senderId: UUID())

        let first = await pipeline.enqueue(GameMessageEvent(model: message, origin: .direct(UUID())))
        let second = await pipeline.enqueue(GameMessageEvent(model: message, origin: .sharePlay(UUID())))

        #expect(first)
        #expect(second)
    }

    @Test("cancelled pipeline rejects new messages")
    func cancelledPipelineRejectsNewMessages() async {
        let pipeline = GameMessagePipeline()
        await pipeline.cancelAll()

        let queued = await pipeline.enqueue(GameMessageEvent(model: Self.message(counter: 1, senderId: UUID()), origin: .direct(UUID())))

        #expect(!queued)
    }

    private static func message(counter: Int, senderId: UUID, dataId: UUID = UUID()) -> GameNetworkModel {
        let gameConfig = GameConfigModel(
            id: senderId,
            state: .started,
            master: MasterGameModel(id: UUID(), type: .master, name: "Master")
        )
        let data = NetworkCodableDataType(id: dataId, type: .photo, version: 1, data: nil)
        return GameNetworkModel(counter: counter, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: gameConfig, data: data)
    }
}

// MARK: - MasterController lostPlayer integration tests

@Suite("MasterController lostPlayer")
@MainActor
struct MasterControllerLostPlayerTests {

    @Test("lostPlayer is a no-op when the connectionId is unknown")
    func lostPlayerNoOpForUnknownConnection() async throws {
        let env = try await ConnectionTestEnvironment.make()

        await env.master.lostPlayer(for: UUID())

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer removes the player from the roster when their connectionId is known")
    func lostPlayerRemovesKnownPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let connId = UUID()

        await env.master.receivedProcess(env.playerMessage, connectionId: connId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        await env.master.lostPlayer(for: connId)

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer removes only the departed player from audio availability reports")
    func lostPlayerPrunesDepartedPlayerFromAudioReports() async throws {
        // Given
        let env = try await ConnectionTestEnvironment.make()
        let departingConnectionId = UUID()
        let remainingConnectionId = UUID()
        let departingPlayerId = env.playerMessage.sender.id
        let remainingPlayerId = UUID()
        let remainingPlayerConfig = GameConfigModel(
            id: remainingPlayerId,
            state: .started,
            master: .empty
        )
        let remainingPlayerMessage = GameNetworkModel(
            counter: 0,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: remainingPlayerConfig,
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: remainingPlayerId, type: .player, name: "Remaining Player")
            ]),
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        )
        await env.master.receivedProcess(env.playerMessage, connectionId: departingConnectionId)
        await env.master.receivedProcess(remainingPlayerMessage, connectionId: remainingConnectionId)

        let sharedAudioId = UUID()
        let departingOnlyAudioId = UUID()
        env.root.audioRoot.audioGameControllable.applyAudio(
            id: sharedAudioId,
            for: [departingPlayerId, remainingPlayerId]
        )
        env.root.audioRoot.audioGameControllable.applyAudio(
            id: departingOnlyAudioId,
            for: [departingPlayerId]
        )
        #expect(
            Set(env.root.audioRoot.gameControllable.gameModel.playerReport(for: sharedAudioId)) ==
                [departingPlayerId, remainingPlayerId]
        )

        // When
        await env.master.lostPlayer(for: departingConnectionId)

        // Then
        let audioReports = env.root.audioRoot.gameControllable.gameModel.playerReports
        #expect(audioReports.values.allSatisfy { !$0.contains(departingPlayerId) })
        #expect(audioReports[sharedAudioId]?.contains(remainingPlayerId) == true)
    }

    @Test("lostPlayer for the old connectionId does not remove a player who has already reconnected")
    func lostPlayerDoesNotRemoveReconnectedPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let oldConnId = UUID()
        let newConnId = UUID()

        // Initial connection
        await env.master.receivedProcess(env.playerMessage, connectionId: oldConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // Player reconnects on a new connectionId before the old one fires lostPlayer
        await env.master.receivedProcess(env.playerMessage, connectionId: newConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // Old connection close event fires — must not evict the still-live player
        await env.master.lostPlayer(for: oldConnId)

        #expect(
            env.root.gameModel.gameRoster.players.count == 1,
            "reconnected player must stay in the roster when the old connectionId fires lostPlayer"
        )
    }

    @Test("lostPlayer for new connectionId removes player after reconnect and second drop")
    func lostPlayerRemovesPlayerOnNewConnectionDrop() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let oldConnId = UUID()
        let newConnId = UUID()

        await env.master.receivedProcess(env.playerMessage, connectionId: oldConnId)
        await env.master.receivedProcess(env.playerMessage, connectionId: newConnId)
        try #require(env.root.gameModel.gameRoster.players.count == 1)

        // New connection also drops — player must be removed
        await env.master.lostPlayer(for: newConnId)

        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }
}

@Suite("MasterController direct and proxy paths")
@MainActor
struct MasterControllerDirectProxyTests {

    @Test("start, stop, and send use the injected network stores")
    func startStopAndSendUseNetworkStores() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false, directStreaming: true)
        let playerId = UUID()
        let hiddenPlayerId = UUID()
        env.root.gameModel.gameRoster = GameRosterModel(
            players: [
                PlayerGameModel(id: playerId, type: .player, name: "Visible"),
                PlayerGameModel(id: hiddenPlayerId, type: .observer, name: "Hidden")
            ]
        )
        env.root.gameModel.gameControl = GameControlModel(
            controls: [
                SharingControlModel(id: playerId, name: "Visible", show: true),
                SharingControlModel(id: hiddenPlayerId, name: "Hidden", show: false)
            ]
        )
        let data = NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)

        await env.master.start()
        await env.master.send(updated: data)
        await env.master.game(message: data, actionType: .generic, playerId: playerId)
        await env.master.stop()

        #expect(env.directMasterSpy.calledStartStreaming == 1)
        #expect(env.proxyMasterSpy.calledStartProxyStreaming == 1)
        #expect(env.directMasterSpy.calledSendResponseAll == 2)
        #expect(env.directMasterSpy.calledStopStreaming == 1)
        #expect(env.directPlayerSpy.calledStop == 1)
        #expect(env.root.gameModel.gameRoster.players.isEmpty)
        #expect(env.root.gameModel.gameControl.controls.isEmpty)

        let filteredMessage = try #require(env.directMasterSpy.sendResponseData as? GameNetworkModel)
        // Targeting replaced the controls filter: the message is addressed to
        // the player, the master state stays complete.
        #expect(filteredMessage.targetId == playerId)
        #expect(filteredMessage.masterState?.controls.map(\.id) == [playerId, hiddenPlayerId])
    }

    @Test("direct receive, ready, and file receive process messages")
    func directReceiveAndFileReceiveProcessMessages() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let connectionId = UUID()
        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Player")])
        let data = NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        let message = GameNetworkModel(
            counter: 5,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: data
        )

        await env.master.ready(for: connectionId)
        await env.master.received(message, connectionId: connectionId)
        await env.master.receivedFile(GameNetworkModel(
            counter: 6,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: data
        ))
        await env.master.receivedFile(GameNetworkModel(
            counter: 7,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: env.root.gameModel.gameConfig,
            gameRoster: playerRoster,
            data: data
        ))

        #expect(env.root.gameModel.gameRoster.players.map(\.id) == [playerId])
        #expect(env.master.gameModel.connectIDPlayers[connectionId] == playerId)
    }

    @Test("proxy ready sends the selected character to a connection")
    func proxyReadySendsSelectedCharacter() async throws {
        let env = try await MasterControllerHarness.make(asProxy: true)
        let characterId = await env.root.characterRoot.itemController.addNew(type: .character)
        env.root.characterRoot.editController.reset(name: "Proxy Hero", itemId: characterId)
        let playerId = env.root.gameModel.gameConfig.id
        env.root.gameModel.gameRoster = GameRosterModel(players: [
            PlayerGameModel(id: playerId, type: .proxy, name: "Proxy", characterId: characterId)
        ])

        let connectionId = UUID()
        await env.master.readyProxy(for: connectionId)

        let sent = try #require(env.proxyMasterSpy.sendResponseData as? GameNetworkModel)
        #expect(env.proxyMasterSpy.calledSendResponseId == 1)
        #expect(sent.data.type == .value)
        #expect(sent.data.id == characterId)
    }

    @Test("proxy messages are never relayed raw to the master network")
    func proxyMessageIsNotRelayedRawToMaster() async throws {
        let env = try await MasterControllerHarness.make(asProxy: true)
        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let message = GameNetworkModel(
            counter: 9,
            proxyCounter: 1,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: "Remote")]),
            data: NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: nil)
        )

        await env.master.receivedServerProxy(message)

        // The proxy stays invisible: nothing goes upstream with its identity,
        // and it never enters the host's roster.
        #expect(env.directPlayerSpy.calledRequest == 0)
        #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("weather and game handlers cover report, reveal, and screen updates")
    func weatherAndGameHandlers() async throws {
        let env = try await MasterControllerHarness.make(asProxy: false)
        let weatherId = await env.root.weatherRoot.itemController.addNew(type: .scenario)
        env.root.weatherRoot.editController.reset(name: "Storm", itemId: weatherId)
        let playerConfig = GameConfigModel(id: UUID(), state: .started, master: .empty)
        let weatherData = try await env.root.weatherRoot.gameControllable.createGameData(for: weatherId)

        let reveal = GameNetworkModel(counter: 11, proxyCounter: 0, type: .reveal, subType: .show, gameConfig: playerConfig, data: weatherData)
        let revealed = try await env.master.handle(reveal)
        #expect(revealed?.id == weatherId)
        #expect(revealed?.type == .weather)

        let ok = GameNetworkModel(counter: 12, proxyCounter: 0, type: .update, subType: .ok, gameConfig: playerConfig, data: weatherData)
        let okResult = try await env.master.handle(ok)
        #expect(okResult == nil)

        let screenData = Data("screen".utf8)
        let gameMessage = GameNetworkModel(
            counter: 13,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: playerConfig,
            data: NetworkCodableDataType(id: UUID(), type: .game, version: 1, data: screenData)
        )
        let gameResult = try await env.master.handle(gameMessage)
        #expect(gameResult == nil)
        #expect(env.root.gameModel.playerScreens[playerConfig.id] == screenData)
    }
}

// MARK: - Test environment

private struct ConnectionTestEnvironment {
    let master: MasterController
    let root: GameRoot
    let playerMessage: GameNetworkModel

    static func make() async throws -> ConnectionTestEnvironment {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "TestMaster")
        )
        await root.gameModel.reset(gameConfig: masterConfig)
        let master = await MasterController(root: root, asProxy: false)

        let playerId = UUID()
        let playerConfig = GameConfigModel(id: playerId, state: .started, master: .empty)
        let playerRoster = GameRosterModel(
            players: [PlayerGameModel(id: playerId, type: .player, name: "TestPlayer")]
        )
        let playerMessage = GameNetworkModel(
            counter: 0,
            proxyCounter: 0,
            type: .store,
            subType: .store,
            gameConfig: playerConfig,
            gameRoster: playerRoster,
            data: NetworkCodableDataType(id: UUID(), type: .setting, version: 0, data: nil)
        )

        return ConnectionTestEnvironment(master: master, root: root, playerMessage: playerMessage)
    }
}

@MainActor
private struct MasterControllerHarness {
    let root: GameRoot
    let master: MasterController
    let directMasterSpy: MasterNetworkControllableMock
    let proxyMasterSpy: MasterNetworkControllableMock
    let directPlayerSpy: PlayerStoreAbstractionMock
    let proxyPlayerSpy: PlayerStoreAbstractionMock

    static func make(asProxy: Bool, directStreaming: Bool = false) async throws -> MasterControllerHarness {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)

        let directMasterModel = MasterNetworkNodel(name: "DirectMaster")
        directMasterModel.isStreaming = directStreaming
        let proxyMasterModel = MasterNetworkNodel(name: "ProxyMaster")
        let directMasterSpy = MasterNetworkControllableMock(networkModel: directMasterModel)
        let proxyMasterSpy = MasterNetworkControllableMock(networkModel: proxyMasterModel)
        let directPlayerSpy = PlayerStoreAbstractionMock()
        let proxyPlayerSpy = PlayerStoreAbstractionMock()

        let directNetwork = GameNetworkController(
            name: "Direct",
            proxy: false,
            masterBuilder: { _, _ in directMasterSpy },
            playerBuilder: { _, _ in directPlayerSpy }
        )
        let proxyNetwork = GameNetworkController(
            name: "Proxy",
            proxy: true,
            masterBuilder: { _, _ in proxyMasterSpy },
            playerBuilder: { _, _ in proxyPlayerSpy }
        )

        root.networkStore = directNetwork
        root.networkProxyStore = proxyNetwork

        let masterId = UUID()
        let masterModel = MasterGameModel(id: masterId, type: .master, name: "Master", adventureId: UUID(), adventureTitle: "Adventure")
        root.gameModel.reset(gameConfig: GameConfigModel(id: masterId, state: .started, master: masterModel))
        let master = MasterController(root: root, asProxy: asProxy)

        return MasterControllerHarness(
            root: root,
            master: master,
            directMasterSpy: directMasterSpy,
            proxyMasterSpy: proxyMasterSpy,
            directPlayerSpy: directPlayerSpy,
            proxyPlayerSpy: proxyPlayerSpy
        )
    }
}
