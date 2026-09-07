// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

// MARK: - Game Messages

extension MasterController {
    /// `.game`-typed envelopes carried a player-screenshot-sharing feature
    /// that had no UI consumer (a write path with no reader, growing
    /// `Data` per player for the session with no eviction) — removed.
    /// See CODE_AUDIT_Game §9.17. The dispatch case is kept as a no-op so an
    /// unrecognized/legacy `.game` message is silently ignored rather than
    /// logged as an error by the `@unknown default` path.
    func handleGame(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        nil
    }
}
