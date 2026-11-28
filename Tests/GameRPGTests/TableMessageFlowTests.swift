// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import TableRPG

@Suite("Table message flow", .serialized)
@MainActor
struct TableMessageFlowTests {
    @Test("Table reveal requests missing data and reuses only the exact received version")
    func revealUsesExactSessionVersion() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let referenceMessage = fixture.masterMessage(
            counter: 1,
            type: .reveal,
            subType: .show,
            data: fixture.reference
        )

        // When - This player has not received the Table during this game.
        let request = try #require(try await fixture.environment.player1.handleTable(referenceMessage))

        // Then
        #expect(request.subType == .show)
        #expect(request.data.id == fixture.tableId)
        #expect(request.data.version == fixture.version)
        #expect(request.data.data == nil)

        // When - The canonical full package arrives.
        let fullMessage = fixture.masterMessage(
            counter: 2,
            type: .reveal,
            subType: .show,
            data: fixture.fullData,
            targetId: fixture.environment.player1Config.id
        )
        let acknowledgement = try #require(try await fixture.environment.player1.handleTable(fullMessage))

        // Then - The receipt preserves the master baseline.
        #expect(acknowledgement.subType == .ok)
        #expect(acknowledgement.data.version == fixture.version)
        #expect(await fixture.environment.player1Root.tableRoot.gameControllable.currentId == fixture.tableId)

        // The exact reference is now available in this session.
        let exactReceipt = try #require(try await fixture.environment.player1.handleTable(referenceMessage))
        #expect(exactReceipt.subType == .ok)
        #expect(exactReceipt.data.version == fixture.version)

        // A different version must never reuse the session copy.
        let otherVersion = fixture.version == 1 ? 2 : 1
        let mismatchedReference = fixture.masterMessage(
            counter: 3,
            type: .reveal,
            subType: .show,
            data: NetworkCodableDataType(id: fixture.tableId, type: .table, version: otherVersion)
        )
        let mismatchRequest = try #require(
            try await fixture.environment.player1.handleTable(mismatchedReference)
        )
        #expect(mismatchRequest.subType == .show)
        #expect(mismatchRequest.data.version == otherVersion)
        #expect(mismatchRequest.data.data == nil)
    }

    @Test("A Table store caches the package without presenting it")
    func storeCachesWithoutPresentation() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let store = fixture.masterMessage(
            counter: 1,
            type: .store,
            subType: .store,
            data: fixture.fullData,
            targetId: fixture.environment.player2Config.id
        )

        // When
        let storeReceipt = try #require(try await fixture.environment.player2.handleTable(store))

        // Then
        #expect(storeReceipt.subType == .ok)
        #expect(storeReceipt.data.version == fixture.version)
        #expect(fixture.environment.player2Root.tableRoot.gameControllable.gameModel.currentItemId == nil)

        // When - A later reveal names the exact cached version.
        let reveal = fixture.masterMessage(
            counter: 2,
            type: .reveal,
            subType: .show,
            data: fixture.reference
        )
        let revealReceipt = try #require(try await fixture.environment.player2.handleTable(reveal))

        // Then
        #expect(revealReceipt.subType == .ok)
        #expect(revealReceipt.data.version == fixture.version)
        #expect(await fixture.environment.player2Root.tableRoot.gameControllable.currentId == fixture.tableId)
    }

    @Test("Master reports only an exact nonzero Table acknowledgement")
    func masterValidatesAcknowledgementVersion() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let fullMessage = fixture.masterMessage(
            counter: 1,
            type: .reveal,
            subType: .show,
            data: fixture.fullData
        )
        let exactReceipt = try #require(try await fixture.environment.player1.handleTable(fullMessage))
        let reports = fixture.environment.masterRoot.tableRoot.gameControllable.gameModel

        var failedReceipt = exactReceipt
        failedReceipt.subType = .failed
        #expect(try await fixture.environment.master.handleTable(failedReceipt) == nil)

        var updateReceipt = exactReceipt
        updateReceipt.type = .update
        #expect(try await fixture.environment.master.handleTable(updateReceipt) == nil)

        var unversionedReceipt = exactReceipt
        unversionedReceipt.data = NetworkCodableDataType(
            id: fixture.tableId,
            type: .table,
            version: 0
        )
        #expect(try await fixture.environment.master.handleTable(unversionedReceipt) == nil)

        let otherVersion = fixture.version == 1 ? 2 : 1
        var staleReceipt = exactReceipt
        staleReceipt.data = NetworkCodableDataType(
            id: fixture.tableId,
            type: .table,
            version: otherVersion
        )
        #expect(try await fixture.environment.master.handleTable(staleReceipt) == nil)
        #expect(reports.playerReport(for: fixture.tableId).isEmpty)

        // When
        #expect(try await fixture.environment.master.handleTable(exactReceipt) == nil)

        // Then
        #expect(reports.playerReport(for: fixture.tableId) == [fixture.environment.player1Config.id])
    }

    @Test("Player ignores Table acknowledgements, failures, and updates")
    func playerIgnoresReceiptsAndUpdates() async throws {
        // Given
        let fixture = try await Self.preparedFixture()

        // When / Then
        for subType in [RPGMessageActionType.ok, .failed] {
            let receipt = fixture.masterMessage(
                counter: subType == .ok ? 1 : 2,
                type: .reveal,
                subType: subType,
                data: fixture.fullData
            )
            #expect(try await fixture.environment.player1.handleTable(receipt) == nil)
        }

        let update = fixture.masterMessage(
            counter: 3,
            type: .update,
            subType: .generic,
            data: fixture.fullData
        )
        #expect(try await fixture.environment.player1.handleTable(update) == nil)
        #expect(fixture.environment.player1.gameModel.gameUpdateType == .none)
        #expect(fixture.environment.player1Root.tableRoot.gameControllable.gameModel.currentItemId == nil)
        #expect(
            fixture.environment.player1Root.tableRoot.gameControllable.gameModel.itemData[fixture.tableId] == nil
        )
    }

    @Test("Master and player never originate Table updates")
    func tableUpdatesAreNotSent() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let masterSends = fixture.environment.masterNetworkSpy.calledSendResponseAll
        let playerSends = fixture.environment.playerNetworkSpy.calledRequest

        // When - Exercise both public game actions and the common send helpers.
        await fixture.environment.master.game(message: fixture.reference, actionType: .generic)
        await fixture.environment.master.send(
            type: .update,
            subtype: .generic,
            updated: fixture.reference
        )
        await fixture.environment.player1.game(message: fixture.reference, actionType: .generic)
        await fixture.environment.player1.send(
            type: .update,
            subType: .generic,
            updated: fixture.reference
        )

        // Then
        #expect(fixture.environment.masterNetworkSpy.calledSendResponseAll == masterSends)
        #expect(fixture.environment.playerNetworkSpy.calledRequest == playerSends)

        let playerUpdate = fixture.playerMessage(
            counter: 4,
            type: .update,
            subType: .generic,
            data: fixture.fullData,
            playerId: fixture.environment.player1Config.id
        )
        #expect(try await fixture.environment.master.handleTable(playerUpdate) == nil)
    }

    @Test("Lost players are removed from Table reports and current-player state")
    func lostPlayerCleansTableReporting() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let player1 = fixture.environment.player1Roster.players[0]
        let player2 = fixture.environment.player2Roster.players[0]
        fixture.environment.masterRoot.gameModel.gameRoster = GameRosterModel(players: [player1, player2])
        fixture.environment.masterRoot.gameModel.gameControl = GameControlModel(controls: [
            SharingControlModel(id: player1.id, name: player1.name, show: true),
            SharingControlModel(id: player2.id, name: player2.name, show: true)
        ])
        await fixture.environment.master.resetPlayers()
        fixture.environment.masterRoot.tableRoot.gameControllable.report(
            itemId: fixture.tableId,
            for: player1.id
        )
        fixture.environment.masterRoot.tableRoot.gameControllable.report(
            itemId: fixture.tableId,
            for: player2.id
        )
        let connectionId = ConnectionController.ID()
        fixture.environment.master.bind(connectionId: connectionId, playerId: player1.id)

        #expect(
            Set(fixture.environment.masterRoot.tableRoot.gameControllable.gameModel.currentPlayers)
                == [player1.id, player2.id]
        )

        // When
        await fixture.environment.master.lostPlayer(for: connectionId)

        // Then
        #expect(
            fixture.environment.masterRoot.tableRoot.gameControllable.gameModel
                .playerReport(for: fixture.tableId) == [player2.id]
        )
        #expect(
            fixture.environment.masterRoot.tableRoot.gameControllable.gameModel.currentPlayers == [player2.id]
        )
    }

    @Test("Proxy Table request is always forwarded to the canonical master")
    func proxyTableRequestAlwaysForwardsUpstream() async throws {
        // Given - The host has received this exact Table in the current session,
        // and its persistent player copy deliberately makes the CRDT merge
        // differ from the master's canonical package.
        let fixture = try await Self.preparedFixture()
        let hostProxySpy = MasterNetworkControllableMock()
        fixture.environment.player1Root.networkProxyStore = GameNetworkController(
            name: "Table proxy echo",
            proxy: true,
            masterBuilder: { _, _ in hostProxySpy },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        let host = fixture.environment.player1
        fixture.environment.player1Root.gameModel.playerController = host
        let localTable = TableModel(
            id: fixture.tableId,
            name: "Player-local Table",
            description: "Must not become the proxy baseline",
            entries: []
        )
        fixture.environment.player1Root.tableRoot.itemController.replace(
            model: localTable,
            isInsert: true
        )
        let fullMessage = fixture.masterMessage(
            counter: 1,
            type: .reveal,
            subType: .show,
            data: fixture.fullData
        )
        _ = try #require(try await host.handleTable(fullMessage))
        #expect(
            fixture.environment.player1Root.tableRoot.gameController
                .gameItem(for: fixture.tableId).version != fixture.version
        )
        let proxyMaster = try #require(host.proxyMasterController)
        let remoteId = UUID()
        let request = GameNetworkModel(
            counter: 2,
            proxyCounter: 1,
            type: .reveal,
            subType: .show,
            gameConfig: GameConfigModel(id: remoteId, state: .started, master: .empty),
            gameRoster: GameRosterModel(players: [
                PlayerGameModel(id: remoteId, type: .proxy, name: "Proxy Mirror")
            ]),
            data: fixture.reference
        )
        let sendsBeforeRequest = fixture.environment.playerNetworkSpy.calledRequest
        let proxyBroadcastsBeforeRequest = hostProxySpy.calledSendResponseAll

        // When
        await proxyMaster.receivedServerProxy(request, connectionId: UUID())

        // Then - It is remapped as the host's request and sent upstream instead
        // of exporting the host's merged Table to the proxy.
        #expect(fixture.environment.playerNetworkSpy.calledRequest == sendsBeforeRequest + 1)
        let forwarded = try #require(
            fixture.environment.playerNetworkSpy.requestData as? GameNetworkModel
        )
        #expect(forwarded.sender.id == fixture.environment.player1Config.id)
        #expect(forwarded.type == .reveal)
        #expect(forwarded.subType == .show)
        #expect(forwarded.data.id == fixture.tableId)
        #expect(forwarded.data.version == fixture.version)
        #expect(forwarded.data.data == nil)
        #expect(
            hostProxySpy.calledSendResponseAll == proxyBroadcastsBeforeRequest
        )
    }

    @Test("A ready connection does not replay a player-merged Table")
    func readyConnectionDoesNotReplayTable() async throws {
        // Given - Table reconnect replay is deliberately unsupported. The
        // current game copy may be a player/master CRDT merge and therefore
        // cannot establish the game master's canonical wire version.
        let fixture = try await Self.preparedFixture()
        #expect(
            await fixture.environment.masterRoot.tableRoot.gameControllable
                .setCurrent(itemId: fixture.tableId)
        )
        let localMasterPlayer = PlayerController(
            root: fixture.environment.masterRoot,
            asGameMaster: true
        )
        localMasterPlayer.gameModel.gameUpdateType = .table
        fixture.environment.masterRoot.gameModel.playerController = localMasterPlayer
        let sendsBeforeReady = fixture.environment.masterNetworkSpy.calledSendResponseId

        // When
        await fixture.environment.master.ready(for: ConnectionController.ID())

        // Then - The game master can explicitly show the Table again if it is
        // still relevant; no potentially noncanonical reference is replayed.
        #expect(
            fixture.environment.masterNetworkSpy.calledSendResponseId == sendsBeforeReady
        )
    }

    @Test("Showing a Table updates the co-located game-master player")
    func showUpdatesLocalMasterTablePresentation() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let localMasterPlayer = PlayerController(
            root: fixture.environment.masterRoot,
            asGameMaster: true
        )
        fixture.environment.masterRoot.gameModel.playerController = localMasterPlayer
        #expect(
            fixture.environment.masterRoot.tableRoot.gameControllable.gameModel.currentItemId == nil
        )

        // When
        await fixture.environment.master.show(for: fixture.reference)

        // Then - the master selects its canonical persistent Table locally,
        // while remote players still receive the lightweight reference.
        #expect(
            fixture.environment.masterRoot.tableRoot.gameControllable.gameModel.currentItemId
                == fixture.tableId
        )
        #expect(localMasterPlayer.gameModel.gameUpdateType == .table)
        let sent = try #require(
            fixture.environment.masterNetworkSpy.sendResponseHistory.last as? GameNetworkModel
        )
        #expect(sent.type == .reveal)
        #expect(sent.subType == .show)
        #expect(sent.data.type == .table)
        #expect(sent.data.id == fixture.tableId)
        #expect(sent.data.data == nil)
    }

    @Test("A late SharePlay participant receives the current Table reference without LAN fan-out")
    func lateSharePlayParticipantReceivesCurrentTableReference() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        #expect(
            await fixture.environment.masterRoot.tableRoot.gameControllable
                .setCurrent(itemId: fixture.tableId)
        )
        let localMasterPlayer = PlayerController(
            root: fixture.environment.masterRoot,
            asGameMaster: true
        )
        localMasterPlayer.gameModel.gameUpdateType = .table
        fixture.environment.masterRoot.gameModel.playerController = localMasterPlayer
        let logsBeforeReady = fixture.environment.masterRoot.gameModel.logs.count
        let lanTargetedSendsBeforeReady = fixture.environment.masterNetworkSpy.calledSendResponseId
        let lanBroadcastsBeforeReady = fixture.environment.masterNetworkSpy.calledSendResponseAll

        // When
        await fixture.environment.master.ready(for: .sharePlay(UUID()))

        // Then - Building the fresh reveal proves Table supersedes any stale
        // Journal presentation. Its SharePlay origin keeps delivery off LAN.
        #expect(fixture.environment.masterRoot.gameModel.logs.count == logsBeforeReady + 1)
        let counter = try #require(fixture.environment.masterRoot.gameModel.logs.last)
        let replay = try #require(fixture.environment.masterRoot.gameModel.logData[counter])
        #expect(replay.type == .reveal)
        #expect(replay.subType == .show)
        #expect(replay.module == .table)
        #expect(replay.itemId == fixture.tableId)
        #expect(fixture.environment.masterNetworkSpy.calledSendResponseId == lanTargetedSendsBeforeReady)
        #expect(fixture.environment.masterNetworkSpy.calledSendResponseAll == lanBroadcastsBeforeReady)
    }
}

private extension TableMessageFlowTests {
    struct Fixture {
        let environment: MultiConnectionTestEnvironment
        let tableId: UUID
        let version: Int
        let reference: NetworkCodableDataType
        let fullData: NetworkCodableDataType

        @MainActor
        func masterMessage(
            counter: Int,
            type: RPGMessageType,
            subType: RPGMessageActionType,
            data: NetworkCodableDataType,
            targetId: UUID? = nil
        ) -> GameNetworkModel {
            environment.masterRoot.gameModel.outgoingMessage(
                counter: counter,
                type: type,
                subType: subType,
                asMaster: true,
                targetId: targetId,
                data: data
            )
        }

        @MainActor
        func playerMessage(
            counter: Int,
            type: RPGMessageType,
            subType: RPGMessageActionType,
            data: NetworkCodableDataType,
            playerId: UUID
        ) -> GameNetworkModel {
            GameNetworkModel(
                counter: counter,
                proxyCounter: 0,
                type: type,
                subType: subType,
                masterId: environment.masterConfig.id,
                sender: GameSenderModel(
                    id: playerId,
                    role: .player,
                    name: "Player",
                    characterId: nil
                ),
                data: data
            )
        }
    }

    static func preparedFixture() async throws -> Fixture {
        let environment = try await MultiConnectionTestEnvironment.create()
        let tableId = await environment.masterRoot.tableRoot.itemController.addNew(type: .item)
        environment.masterRoot.tableRoot.editController.reset(name: "Encounter table", itemId: tableId, forceSave: false)

        let version = await environment.masterRoot.tableRoot.gameControllable.networkVersion(for: tableId)
        try #require(version != 0)
        let reference = await environment.masterRoot.tableRoot.gameControllable.share(id: tableId)
        let fullData = try await environment.masterRoot.tableRoot.gameControllable.createGameData(for: tableId)

        environment.masterRoot.adventureRoot.startGame()
        environment.player1Root.adventureRoot.startGame()
        environment.player2Root.adventureRoot.startGame()
        environment.player3Root.adventureRoot.startGame()

        return Fixture(
            environment: environment,
            tableId: tableId,
            version: version,
            reference: reference,
            fullData: fullData
        )
    }
}
#endif
