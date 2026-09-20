// @copyright André Trettin

#if os(visionOS)

import TabletopKit
import RealityKit

@MainActor
final class GameObserver: TabletopGame.Observer {
    let tabletop: TabletopGame
    let renderer: GameRenderer
    var isMaster: Bool = false
    /// Gates `playerChangedSeats`'s automatic re-claim while a SharePlay group session is active
    /// but `coordinateWithSession(_:)` hasn't attached to it yet. Defaults `false` because this
    /// observer is registered the moment `GameTableModel.init` constructs `tabletopGame`, well
    /// before `GameTableView` learns whether a SharePlay session is involved. If
    /// `playerChangedSeats` fires with `newSeat == nil` for the local player in that window, an
    /// ungated re-claim races the network coordinator exactly like the claim `setupSeating` defers,
    /// crashing a joining player with "Could not find static equipment with identifier: ...".
    /// `setupSeating` sets this `true` for the no-session case, and `RPGSharePlayController` sets it
    /// once its coordinated seat assignment has been submitted.
    var canAutoClaimSeat = false

    init(tabletop: TabletopGame, renderer: GameRenderer) {
        self.tabletop = tabletop
        self.renderer = renderer
    }

    func actionIsPending(_ action: some TabletopAction, oldSnapshot: TableSnapshot, newSnapshot: TableSnapshot) {
        guard let action = action as? UpdateEquipmentAction<DieState> else { return }

        // A value of 0 is the table's "parked, unused slot" sentinel (see `Die20.init`), not a roll.
        if let (die20, state) = newSnapshot.equipment(of: Die20.self, matching: action.equipmentID) {
            if state.value != 0 { die20.playTossSound() }
        } else if let (die, state) = newSnapshot.equipment(of: Die.self, matching: action.equipmentID) {
            if state.value != 0 { die.playTossSound() }
        }
    }

    func playerChangedSeats(_ player: Player, oldSeat: (any TableSeat)?, newSeat: (any TableSeat)?, snapshot: TableSnapshot) {
        if player.id == tabletop.localPlayer.id, newSeat == nil, canAutoClaimSeat {
            reclaimLocalSeat()
        }

        // The local player's own seat claim just landed. It can arrive after `GameTableView`
        // already tried (and, finding no seat yet, no-opped) to mirror the focused dice set, so
        // retry now that a seat exists. Deferred via `Task`, not called inline: this callback fires
        // synchronously from inside TabletopKit's action processing, and the retry fans out into
        // several more `addAction` calls — mutating the session reentrantly from a callback that
        // is already mid-dispatch corrupted it outright.
        if player.id == tabletop.localPlayer.id, newSeat != nil {
            Task { @MainActor [renderer] in
                renderer.game?.applyFocusedDiceRollForLocalSeat?()
            }
        }
    }

    /// Re-claims the seat the local player lost. A player goes back to the seat the deterministic
    /// assignment gave them; `claimAnySeat()` is only the last resort, because it can hand out
    /// seat 0, which belongs to the master.
    private func reclaimLocalSeat() {
        if isMaster {
            tabletop.claimSeat(matching: TableSeatIdentifier(0))
        } else if let assignedSeat = renderer.game?.lastRequestedSeatAssignment?.seatId {
            tabletop.claimSeat(matching: assignedSeat)
        } else {
            tabletop.claimAnySeat()
        }
    }
}

#endif
