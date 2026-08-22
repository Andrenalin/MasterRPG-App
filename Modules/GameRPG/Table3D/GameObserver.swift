// @copyright André Trettin

#if os(visionOS)

import TabletopKit
import RealityKit

@MainActor
class GameObserver: TabletopGame.Observer {
    let tabletop: TabletopGame
    let renderer: GameRenderer
    var isMaster: Bool = false
    /// Gates `playerChangedSeats`'s automatic re-claim below (line ~44) while a
    /// SharePlay group session is active but `coordinateWithSession(_:)` hasn't
    /// attached to it yet. Defaults `false` — not `true` — because this
    /// observer is registered (`tabletopGame.addObserver`) the moment
    /// `GameTableModel.init` constructs `tabletopGame`, which happens well
    /// before `GameTableView` gets a chance to call `setupSeating` and learn
    /// whether a SharePlay session is even involved; if `playerChangedSeats`
    /// fires with `newSeat == nil` for the local player anywhere in that
    /// window (TabletopKit replays/settles initial seat state as part of
    /// constructing a fresh `TableSetup`), an ungated `claimAnySeat()` here
    /// races the network coordinator exactly like the seat claim `setupSeating`
    /// itself defers — see that method's own doc — just earlier and outside
    /// its control, still crashing a joining player with "Could not find
    /// static equipment with identifier: ...". `setupSeating` flips this
    /// `true` immediately for the no-session (local/single-player) case,
    /// where there's no coordinator to race; `RPGSharePlayController` flips
    /// it `true` once its own coordinated seat assignment has actually been
    /// submitted, in both places it does that (the deferred task in
    /// `setup(tabletopGame:gameTableModel:)`, and the session-configure flow
    /// that calls `setupSeatAssignment` directly after an already-attached
    /// `coordinateWithSession`).
    var canAutoClaimSeat = false

    init(tabletop: TabletopGame, renderer: GameRenderer) {
        self.tabletop = tabletop
        self.renderer = renderer
    }

    func actionIsPending(_ action: some TabletopAction, oldSnapshot: TableSnapshot, newSnapshot: TableSnapshot) {
        guard let action = action as? UpdateEquipmentAction<DieState> else { return }

        if let (die20, _) = newSnapshot.equipment(
            of: Die20.self,
            matching: action.equipmentID
        ) {
            die20.playTossSound()
        }
    }

    func playerChangedSeats(_ player: Player, oldSeat: (any TableSeat)?, newSeat: (any TableSeat)?, snapshot: TableSnapshot) {
        if player.id == tabletop.localPlayer.id, newSeat == nil, canAutoClaimSeat {
            if isMaster {
                tabletop.claimSeat(matching: TableSeatIdentifier(0))
            } else {
                tabletop.claimAnySeat()
            }
        }

        // The local player's own seat claim just landed — this can arrive after
        // `GameTableView` already tried (and, finding no seat yet, no-opped) to mirror
        // the locally focused dice set onto the table. Retry now that a seat actually
        // exists, so this seat's dice don't stay unplaced/hidden until the next
        // unrelated roll or focus change. See `GameTableModel.applyFocusedDiceRollForLocalSeat`.
        //
        // Deferred via `Task`, not called inline: `playerChangedSeats` fires synchronously
        // from inside TabletopKit's own action-processing (this is reached from
        // `setupSeating()`'s `claimSeat`/`claimAnySeat` call, on every first load). The retry
        // fans out into up to a dozen more `tabletopGame.addAction` calls — mutating the same
        // session reentrantly, from inside a callback that's already mid-dispatch, corrupted
        // the tabletop session outright (dice, toolbar, and side menu all failing to render).
        // A `Task` runs it on the next run-loop turn instead, off TabletopKit's own call stack.
        if player.id == tabletop.localPlayer.id, newSeat != nil {
            Task { @MainActor [renderer] in
                renderer.game?.applyFocusedDiceRollForLocalSeat?()
            }
        }
    }
}

#endif
