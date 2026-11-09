// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@testable import AdventureRPG
@testable import DiceRPG
@testable import AudioRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import CharacterRPG
@testable import WeatherRPG

/// Regression coverage for the "reconnect against a restarted master" bug: a
/// game master that fully quits and restarts mints a brand-new `master.id`
/// (`GameRoot.startMaster()`), but a player's `gameConfig.master.type` was
/// left pinned at `.master` from the previous session, so
/// `PlayerController`'s `acceptsSessionMessage` guard (`config.master.type
/// == .master` requires an exact `masterId` match) permanently rejected
/// every message from the restarted master — and, transitively, every
/// message this device tried to send back — even though the transport layer
/// itself reported a successful reconnect. Losing the connection must unpin
/// the logical master identity so the next full master broadcast can
/// re-establish authority under its new id.
@Suite("Reconnect to a restarted master re-opens master-identity discovery")
@MainActor
struct RestartedMasterReconnectTests {
    @Test("Losing the master connection unpins the logical master identity")
    func lostConnectionUnpinsMasterIdentity() async {
        let root = GameRoot.previewFixture(game: .player)
        guard let playerController = root.gameModel.playerController else {
            Issue.record("Expected a PlayerController from the preview fixture")
            return
        }

        #expect(root.gameModel.gameConfig.master.type == .master)

        await playerController.lostConnection()

        #expect(root.gameModel.gameConfig.master.type == .notSet)
    }

    @Test("Losing the master via a SharePlay participant departure also unpins the logical master identity")
    func sharePlayParticipantLeftUnpinsMasterIdentity() async {
        let root = GameRoot.previewFixture(game: .player)
        guard let playerController = root.gameModel.playerController else {
            Issue.record("Expected a PlayerController from the preview fixture")
            return
        }
        let participantId = UUID()
        _ = playerController.gameModel.noteSharePlayMasterParticipant(id: participantId)

        await playerController.sharePlayParticipantLeft(id: participantId)

        #expect(root.gameModel.gameConfig.master.type == .notSet)
    }
}

/// CODE_AUDIT_Game_Shareplay §5.3.
@Suite("A master that rejoins under a new SharePlay participant")
@MainActor
struct MasterParticipantChangeTests {
    private func masterMessage(counter: Int, config: GameConfigModel) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: config,
            data: NetworkCodableDataType(id: UUID(), type: .value, version: 1, data: nil)
        )
    }

    @Test("Its first message forgets the counters of the old run, before the old participant's departure is seen")
    func changedParticipantResetsSequences() async throws {
        let root = GameRoot.previewFixture(game: .player)
        let player = try #require(root.gameModel.playerController)
        let config = root.gameModel.gameConfig
        let masterId = config.master.id
        let oldParticipant = UUID()
        let newParticipant = UUID()

        // The old run got as far as counter 50 and presented something.
        let first = masterMessage(counter: 50, config: GameConfigModel(id: masterId, state: .started, master: config.master))
        #expect(await player.acceptsSessionMessage(first, origin: .sharePlay(oldParticipant)))
        #expect(player.gameModel.shouldApplyMasterState(from: masterId, counter: 50))
        player.gameModel.markPresentation(counter: 50, module: .photo, itemId: UUID())
        #expect(!player.gameModel.shouldApplyMasterState(from: masterId, counter: 1))

        // The restarted master speaks from a new participant and counts from one.
        let restarted = masterMessage(counter: 1, config: GameConfigModel(id: masterId, state: .started, master: config.master))
        #expect(await player.acceptsSessionMessage(restarted, origin: .sharePlay(newParticipant)))

        #expect(player.gameModel.shouldApplyMasterState(from: masterId, counter: 1))
        #expect(player.gameModel.isCurrentPresentation(counter: 1, module: .map, itemId: UUID()))
    }

    @Test("The same participant keeps its counters")
    func unchangedParticipantKeepsSequences() async throws {
        let root = GameRoot.previewFixture(game: .player)
        let player = try #require(root.gameModel.playerController)
        let config = root.gameModel.gameConfig
        let masterId = config.master.id
        let participant = UUID()
        let masterConfig = GameConfigModel(id: masterId, state: .started, master: config.master)

        #expect(await player.acceptsSessionMessage(masterMessage(counter: 50, config: masterConfig), origin: .sharePlay(participant)))
        #expect(player.gameModel.shouldApplyMasterState(from: masterId, counter: 50))
        #expect(await player.acceptsSessionMessage(masterMessage(counter: 51, config: masterConfig), origin: .sharePlay(participant)))

        #expect(!player.gameModel.shouldApplyMasterState(from: masterId, counter: 49))
    }
}
