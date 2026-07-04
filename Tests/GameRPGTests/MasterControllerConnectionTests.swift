// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG

// MARK: - MasterControllerModel unit tests

@Suite("MasterControllerModel connection mapping")
@MainActor
struct MasterControllerModelConnectionTests {

    @Test("add registers a new connectionId for a player")
    func addRegistersNewPlayer() async {
        let model = await MasterControllerModel()
        let connId = UUID()
        let playerId = UUID()

        await MainActor.run { model.add(connectionId: connId, playerId: playerId) }

        let registered = await MainActor.run { model.connectIDPlayers[connId] }
        #expect(registered == playerId)
    }

    @Test("add evicts the stale connectionId when the same player reconnects")
    func addEvictsStaleConnectionOnReconnect() async {
        let model = await MasterControllerModel()
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
        let model = await MasterControllerModel()
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

        await #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer removes the player from the roster when their connectionId is known")
    func lostPlayerRemovesKnownPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let connId = UUID()

        await env.master.receivedProcess(env.playerMessage, connectionId: connId)
        try #require(await env.root.gameModel.gameRoster.players.count == 1)

        await env.master.lostPlayer(for: connId)

        await #expect(env.root.gameModel.gameRoster.players.isEmpty)
    }

    @Test("lostPlayer for the old connectionId does not remove a player who has already reconnected")
    func lostPlayerDoesNotRemoveReconnectedPlayer() async throws {
        let env = try await ConnectionTestEnvironment.make()
        let oldConnId = UUID()
        let newConnId = UUID()

        // Initial connection
        await env.master.receivedProcess(env.playerMessage, connectionId: oldConnId)
        try #require(await env.root.gameModel.gameRoster.players.count == 1)

        // Player reconnects on a new connectionId before the old one fires lostPlayer
        await env.master.receivedProcess(env.playerMessage, connectionId: newConnId)
        try #require(await env.root.gameModel.gameRoster.players.count == 1)

        // Old connection close event fires — must not evict the still-live player
        await env.master.lostPlayer(for: oldConnId)

        await #expect(
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
        try #require(await env.root.gameModel.gameRoster.players.count == 1)

        // New connection also drops — player must be removed
        await env.master.lostPlayer(for: newConnId)

        await #expect(env.root.gameModel.gameRoster.players.isEmpty)
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
