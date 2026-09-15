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

/// Regression coverage for CODE_AUDIT_Reconnect §5.2 / §5.5: the co-located
/// game-master's own local `PlayerController` never goes through the network
/// `ready()`/`lostConnection()` delegate lifecycle (`setupLocal()` wires it
/// directly, and `GameNetworkController` explicitly skips calling `ready()`
/// for it), so nothing ever flipped `lostMaster` away from its default. Left
/// unfixed, every "Connection Lost" UI/logic guard that reads it for the
/// game master's own device would trip regardless of the actual connection —
/// this suite locks in that it doesn't.
@Suite("Co-located master's own PlayerController reconnect state")
@MainActor
struct CoLocatedMasterReconnectTests {
    @Test("A co-located game master's own local PlayerController starts connected")
    func coLocatedMasterStartsConnected() {
        let root = GameRoot.previewFixture(game: .master)
        let playerController = root.gameModel.playerController

        #expect(playerController?.gameModel.asGameMaster == true)
        #expect(playerController?.gameModel.lostMaster == false)
        #expect(playerController?.gameModel.canSendCharacter == true)
    }

    @Test("A remote (non-co-located) PlayerController still starts as lost until ready() reports in")
    func remotePlayerStartsLostUntilReady() {
        // Contrast case: a real remote player *does* go through the network
        // lifecycle, so it must keep the original "lost until ready()"
        // default the co-located case is deliberately exempted from.
        let root = GameRoot.previewFixture(game: .player)
        let playerController = root.gameModel.playerController

        #expect(playerController?.gameModel.asGameMaster == false)
        #expect(playerController?.gameModel.lostMaster == true)
        #expect(playerController?.gameModel.canSendCharacter == false)
    }

    @Test("ready() clears lostMaster for a remote player, matching the co-located master's already-connected state")
    func readyClearsLostMasterForRemotePlayer() async {
        let root = GameRoot.previewFixture(game: .player)
        guard let playerController = root.gameModel.playerController else {
            Issue.record("Expected a PlayerController from the preview fixture")
            return
        }

        await playerController.ready()

        #expect(playerController.gameModel.lostMaster == false)
    }
}
