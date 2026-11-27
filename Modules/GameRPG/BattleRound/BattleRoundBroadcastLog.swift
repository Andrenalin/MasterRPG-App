// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

/// What `BattleRoundController` last broadcast, so an action that changed
/// nothing a participant can see sends nothing.
///
/// The controller's own sends are recorded; every other map-state or
/// battle-round send of the game (the 3D pin menu, a map edit, a full map
/// update) makes the log forget that kind (`noteSend`), because after an
/// A → B → A sequence the controller's last value no longer is what the
/// players have, and the revert was never sent. See CODE_AUDIT_29 §5.6.
/// Both are compared as values, not as encoded messages: the map state's
/// JSON has no fixed key order, and the battle round's envelope carries the
/// map's generation, which is not part of the round.
///
/// Lives on `GameRoot` because the controller is a stateless struct.
@MainActor
final class BattleRoundBroadcastLog {
    private var lastMapState: MapLiveState?
    private var lastBattleRound: BattleRoundNetworkState?
    /// Set while the controller hands its own message to the network actions.
    private var isRecordingOwnSend = false

    /// `true` when `state` differs from the last map state sent, and records it as sent.
    func shouldSend(mapState state: MapLiveState) -> Bool {
        guard lastMapState != state else { return false }
        lastMapState = state
        return true
    }

    /// `true` when `state` differs from the last battle round sent, and records it as sent.
    func shouldSend(battleRound state: BattleRoundNetworkState) -> Bool {
        guard lastBattleRound != state else { return false }
        lastBattleRound = state
        return true
    }

    /// Sends `state` with `send` unless it equals the last map state sent, and records it.
    func send(mapState state: MapLiveState, _ send: () -> Void) {
        guard shouldSend(mapState: state) else { return }
        recordingOwnSend(send)
    }

    /// Sends `state` with `send` unless it equals the last battle round sent, and records it.
    func send(battleRound state: BattleRoundNetworkState, _ send: () -> Void) {
        guard shouldSend(battleRound: state) else { return }
        recordingOwnSend(send)
    }

    private func recordingOwnSend(_ send: () -> Void) {
        isRecordingOwnSend = true
        defer { isRecordingOwnSend = false }
        send()
    }

    /// Called for every game message that leaves this device. A map-state or battle-round
    /// message (or a full map update, which carries the pins) another path sent makes the log
    /// forget the value it recorded for that kind.
    func noteSend(actionType: RPGMessageActionType, type: NetworkModules?) {
        guard !isRecordingOwnSend else { return }
        switch actionType {
        case .mapState:
            lastMapState = nil
        case .battleRound:
            lastBattleRound = nil
        default:
            if type == .map {
                lastMapState = nil
            }
        }
    }

    /// A stopped game forgets what was sent; the next one starts from nothing.
    func reset() {
        lastMapState = nil
        lastBattleRound = nil
    }
}
