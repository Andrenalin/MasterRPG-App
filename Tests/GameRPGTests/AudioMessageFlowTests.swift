// @copyright André Trettin

#if canImport(Testing)
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import CoreRPG
@testable import GameRPG

@MainActor
extension MultiConnectionAudioTests {
    @Test("Connected player reports database audio even when it is not in game memory")
    func connectedPlayerReportsDatabaseAudio() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        try await Self.importAudioFixture(into: env.player1Root.adventureRoot)
        let databaseIds = Set(env.player1Root.audioRoot.itemController.itemDataModel.items)
        #expect(!databaseIds.isEmpty)
        #expect(env.player1Root.audioRoot.gameController.gameModel.items.isEmpty)

        // When
        await env.player1.ready()

        // Then
        let report = try #require(env.playerNetworkSpy.requestData as? GameNetworkModel)
        let list = try #require(AudioListRequest.decodeData(of: report.data.data))
        #expect(report.subType == .audioList)
        #expect(Set(list.list) == databaseIds)
        #expect(list.players.isEmpty)
    }

    @Test("Master merges each player report and rebroadcasts an authoritative list")
    func masterConvergesAudioReports() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        let reports = [env.player1Root, env.player2Root, env.player3Root].map {
            Self.audioReport(from: $0, availableIds: [audioId])
        }
        let baseline = env.masterNetworkSpy.calledSendResponseAll

        // When
        for report in reports {
            _ = try await env.master.handleAudio(report)
        }

        // Then
        #expect(env.masterNetworkSpy.calledSendResponseAll == baseline + reports.count)
        let update = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        let authoritative = try #require(AudioListRequest.decodeData(of: update.data.data))
        #expect(update.sender.isMaster)
        #expect(update.subType == .audioList)
        #expect(Set(authoritative.players[audioId] ?? []) == Set([
            env.masterConfig.id,
            env.player1Config.id,
            env.player2Config.id,
            env.player3Config.id
        ]))
    }

    @Test("Play waits and sends journaled audio only to missing player ids")
    func playWaitsForMissingPlayers() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        try await Self.reportAvailability(
            in: env,
            audioId: audioId,
            availablePlayerIds: [env.player1Config.id, env.player3Config.id]
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        let playData = env.masterRoot.audioRoot.gameController.requestPlay(id: audioId)

        // When
        await env.master.game(message: playData, actionType: .playAudio)

        // Then
        let sent = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
        #expect(sent.count == 1)
        let transfer = try #require(sent.first)
        #expect(transfer.type == .store)
        #expect(transfer.subType == .show)
        #expect(transfer.targetId == env.player2Config.id)
        #expect(transfer.data.id == audioId)
        #expect(transfer.data.data != nil)
        #expect(MasterController.usesFileJournal(for: transfer))
        #expect(env.masterRoot.audioRoot.audioController.model.currentId == nil)
    }

    @Test("Last successful receipt publishes the list before starting pending play")
    func receiptCompletesPendingPlay() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        env.player2Root.adventureRoot.startGame()
        try await Self.reportAvailability(
            in: env,
            audioId: audioId,
            availablePlayerIds: [env.player1Config.id, env.player3Config.id]
        )
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        let transfer = try #require(env.masterNetworkSpy.sendResponseData as? GameNetworkModel)
        let receipt = try #require(try await env.player2.handleAudio(transfer))
        #expect(receipt.subType == .ok)
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        // When
        _ = try await env.master.handleAudio(receipt)

        // Then
        let sent = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
        #expect(sent.map(\.subType) == [.audioList, .playAudio])
        #expect(env.masterRoot.audioRoot.audioController.model.currentId == audioId)

        let play = try #require(sent.last)
        _ = try await env.player2.handleAudio(play)
        #expect(env.player2Root.audioRoot.audioController.model.currentId == audioId)
    }

    @Test("Reconnect report retries a pending transfer for an unavailable player")
    func reconnectReportRetriesPendingTransfer() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        try await Self.reportAvailability(
            in: env,
            audioId: audioId,
            availablePlayerIds: [env.player1Config.id, env.player3Config.id]
        )
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count

        // When - Player 2 reconnects and its fresh database report still lacks the audio.
        _ = try await env.master.handleAudio(Self.audioReport(from: env.player2Root, availableIds: []))

        // Then - The list converges first, followed by a new targeted transfer.
        let sent = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
        #expect(sent.map(\.subType) == [.audioList, .show])
        #expect(sent.last?.targetId == env.player2Config.id)
    }

    @Test("Pause cancels a pending play while a player is missing audio")
    func pauseCancelsPendingPlay() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let audioId = try #require(env.masterRoot.audioRoot.itemController.itemDataModel.items.last)
        try await Self.reportAvailability(
            in: env,
            audioId: audioId,
            availablePlayerIds: [env.player1Config.id, env.player3Config.id]
        )
        await env.master.game(
            message: env.masterRoot.audioRoot.gameController.requestPlay(id: audioId),
            actionType: .playAudio
        )
        let pauseRequest = AudioPlayRequest(id: audioId, shouldPlay: false)
        let pauseData = NetworkCodableDataType(
            id: audioId,
            type: .audio,
            version: 0,
            data: pauseRequest.encodeData()
        )

        // When
        await env.master.game(message: pauseData, actionType: .playAudio)
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        _ = try await env.master.handleAudio(Self.audioReport(from: env.player2Root, availableIds: [audioId]))

        // Then - Availability still synchronizes, but the cancelled play is not restarted.
        let sent = env.masterNetworkSpy.sendResponseHistory
            .dropFirst(baseline)
            .compactMap { $0 as? GameNetworkModel }
        #expect(sent.map(\.subType) == [.audioList])
        #expect(env.masterRoot.audioRoot.audioController.model.currentId == nil)
    }

    @Test("Player full audio upload uses journal but play request does not")
    func playerUploadJournalPolicy() async throws {
        // Given
        let audioId = UUID()
        let fullAudio = NetworkCodableDataType(
            id: audioId,
            type: .audio,
            version: 1,
            data: Data([0x01])
        )
        let play = NetworkCodableDataType(
            id: audioId,
            type: .audio,
            version: 1,
            data: AudioPlayRequest(id: audioId, shouldPlay: true).encodeData()
        )

        // Then
        #expect(PlayerController.usesFileJournal(type: .update, subType: .generic, data: fullAudio))
        #expect(!PlayerController.usesFileJournal(type: .update, subType: .playAudio, data: play))
    }

    @Test("Player ignores peer play request and accepts master play command")
    func onlyMasterCanTriggerPlayerPlayback() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let audioId = UUID()
        let playData = NetworkCodableDataType(
            id: audioId,
            type: .audio,
            version: 0,
            data: AudioPlayRequest(id: audioId, shouldPlay: true).encodeData()
        )
        let peerCommand = env.player2Root.gameModel.outgoingMessage(
            counter: 1,
            type: .update,
            subType: .playAudio,
            asMaster: false,
            data: playData
        )

        // When
        _ = try await env.player1.handleAudio(peerCommand)

        // Then
        #expect(env.player1Root.audioRoot.gameController.gameModel.playerReport(for: audioId).isEmpty)

        let masterCommand = env.masterRoot.gameModel.outgoingMessage(
            counter: 2,
            type: .update,
            subType: .playAudio,
            asMaster: true,
            data: playData
        )
        _ = try await env.player1.handleAudio(masterCommand)
        #expect(env.player1Root.audioRoot.gameController.gameModel.playerReport(for: audioId).contains(env.masterConfig.id))
    }

    @Test("SharePlay receivers load while the master device initiates coordinated playback")
    func sharePlayPlaybackPolicy() {
        #expect(PlayerController.shouldStartAudioPlayback(isSharePlayActive: false, asGameMaster: false))
        #expect(PlayerController.shouldStartAudioPlayback(isSharePlayActive: true, asGameMaster: true))
        #expect(!PlayerController.shouldStartAudioPlayback(isSharePlayActive: true, asGameMaster: false))
    }
}

private extension MultiConnectionAudioTests {
    static func importAudioFixture(into root: AdventureRootModel) async throws {
        let url = try #require(
            ResourcesDebug.bundle.url(forResource: ResourcesDebug.audioTestData, withExtension: "gmz")
        )
        let task = root.importController.importUrl(from: url)
        _ = try await task.value
    }

    static func preparedEnvironment() async throws -> MultiConnectionTestEnvironment {
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(into: env.masterRoot.adventureRoot)
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.audioTestData,
            itemCounter: 3
        )
        env.masterRoot.adventureRoot.startGame()
        env.masterRoot.gameModel.gameRoster = GameRosterModel(players: [
            env.player1Roster.players[0],
            env.player2Roster.players[0],
            env.player3Roster.players[0]
        ])
        env.masterRoot.gameModel.gameControl = GameControlModel(controls: [
            SharingControlModel(id: env.player1Config.id, name: env.player1Roster.players[0].name, show: true),
            SharingControlModel(id: env.player2Config.id, name: env.player2Roster.players[0].name, show: true),
            SharingControlModel(id: env.player3Config.id, name: env.player3Roster.players[0].name, show: true)
        ])
        await env.master.resetPlayers()
        return env
    }

    static func audioReport(from root: GameRoot, availableIds: [UUID]) -> GameNetworkModel {
        let request = AudioListRequest(list: availableIds, players: [:])
        return root.gameModel.outgoingMessage(
            counter: 1,
            type: .update,
            subType: .audioList,
            asMaster: false,
            data: NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: request.encodeData())
        )
    }

    static func reportAvailability(
        in env: MultiConnectionTestEnvironment,
        audioId: UUID,
        availablePlayerIds: Set<UUID>
    ) async throws {
        let players: [(GameRoot, UUID)] = [
            (env.player1Root, env.player1Config.id),
            (env.player2Root, env.player2Config.id),
            (env.player3Root, env.player3Config.id)
        ]
        for (root, id) in players {
            let availableIds = availablePlayerIds.contains(id) ? [audioId] : []
            _ = try await env.master.handleAudio(Self.audioReport(from: root, availableIds: availableIds))
        }
    }
}
#endif
