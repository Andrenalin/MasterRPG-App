// @copyright André Trettin

import Foundation

// Split out of BattleRoundModel.swift — see CODE_AUDIT §9.13.

extension BattleRoundModel {
    @discardableResult
    func applyRemoteState(_ state: BattleRoundNetworkState) -> Bool {
        guard state.sequence > networkSequence else { return false }
        mapId = state.mapId
        isRunning = state.isRunning
        roundCounter = state.roundCounter
        networkSequence = state.sequence
        presentedActivePinId = state.activePinId
        activeAttackerId = state.activePinId.flatMap { combatant(pinId: $0)?.id }
        rollRecipientCombatantId = activeAttackerId
        return true
    }

    /// Clears just the sequence gate, without touching the rest of the
    /// displayed round state, so a lost/rejoined connection can accept the
    /// next authoritative update even if the master restarted its own
    /// sequence lower than what this device last saw. A full `reset()` would
    /// also blank the visible round/combatants until the resync arrives.
    /// See CODE_AUDIT_Game §5.6.
    public func resetNetworkSequence() {
        networkSequence = 0
    }

    func networkState() -> BattleRoundNetworkState? {
        guard let mapId else { return nil }
        return BattleRoundNetworkState(
            mapId: mapId,
            isRunning: isRunning,
            roundCounter: roundCounter,
            activePinId: activePinId,
            sequence: networkSequence
        )
    }
}
