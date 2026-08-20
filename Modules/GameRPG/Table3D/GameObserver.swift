// @copyright André Trettin

#if os(visionOS)

import TabletopKit
import RealityKit

@MainActor
class GameObserver: TabletopGame.Observer {
    let tabletop: TabletopGame
    let renderer: GameRenderer
    var isMaster: Bool = false

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

    func actionWasConfirmed(_ action: some TabletopAction, oldSnapshot: TableSnapshot, newSnapshot: TableSnapshot) {
        // A die's value (which slot is active/inactive, and what it shows)
        // just changed — either a manual toss or `GameTableModel.applyDiceRoll`
        // reshaping a seat's dice to match its locally focused set. Re-derive
        // visibility from the fresh snapshot on every participant, the same
        // way `playerChangedSeats` does for seat occupancy. See
        // `GameTableModel.updateDiceVisibility(using:)`.
        guard action is UpdateEquipmentAction<DieState> else { return }
        renderer.game?.updateDiceVisibility(using: newSnapshot)
    }

    func playerChangedSeats(_ player: Player, oldSeat: (any TableSeat)?, newSeat: (any TableSeat)?, snapshot: TableSnapshot) {
        if player.id == tabletop.localPlayer.id, newSeat == nil {
            if isMaster {
                tabletop.claimSeat(matching: TableSeatIdentifier(0))
            } else {
                tabletop.claimAnySeat()
            }
        }
        // Any seat's occupancy just changed (this player's, or another
        // participant's over SharePlay) — re-derive which seats' dice
        // should be visible from the fresh snapshot this callback already
        // received.
        renderer.game?.updateDiceVisibility(using: snapshot)
    }
}

#endif
