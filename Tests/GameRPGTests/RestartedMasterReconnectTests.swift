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
