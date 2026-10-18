// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

/// What `BattleRoundController` last broadcast, so an action that changed
/// nothing a participant can see sends nothing.
///
/// Only this controller's own sends are recorded. That is enough to skip
/// safely: a message is skipped only when it would carry the same state as
/// one that already went out, and every other change to the map or the round
/// is sent by the path that made it. Both are compared as values, not as
/// encoded messages: the map state's JSON has no fixed key order, and the
/// battle round's envelope carries the map's generation, which is not part
/// of the round.
///
/// Lives on `GameRoot` because the controller is a stateless struct.
@MainActor
final class BattleRoundBroadcastLog {
    private var lastMapState: MapLiveState?
    private var lastBattleRound: BattleRoundNetworkState?

    /// `true` when `state` differs from the last map state sent, and
    /// records it as sent.
    func shouldSend(mapState state: MapLiveState) -> Bool {
        guard lastMapState != state else { return false }
        lastMapState = state
        return true
    }

    /// `true` when `state` differs from the last battle round sent, and
    /// records it as sent.
    func shouldSend(battleRound state: BattleRoundNetworkState) -> Bool {
        guard lastBattleRound != state else { return false }
        lastBattleRound = state
        return true
    }

    /// A stopped game forgets what was sent; the next one starts from nothing.
    func reset() {
        lastMapState = nil
        lastBattleRound = nil
    }
}
