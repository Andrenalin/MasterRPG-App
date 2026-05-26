// @copyright André Trettin

#if os(visionOS)

import TabletopKit
import RealityKit

class GameObserver: TabletopGame.Observer {
    let tabletop: TabletopGame
    let renderer: GameRenderer
    var isMaster: Bool = false

    init(tabletop: TabletopGame, renderer: GameRenderer) {
        self.tabletop = tabletop
        self.renderer = renderer
    }

    func actionIsPending(_ action: some TabletopAction, oldSnapshot: TableSnapshot, newSnapshot: TableSnapshot) {
        if let action = action as? MoveEquipmentAction {
            if let (die, _) = newSnapshot.equipment(of: Die.self, matching: action.equipmentID) {
                Task { @MainActor in
                    die.playTossSound()
                }
                return
            }
        }
    }

    func actionWasConfirmed(_ action: some TabletopAction, oldSnapshot: TableSnapshot, newSnapshot: TableSnapshot) {
    }

    func playerChangedSeats(_ player: Player, oldSeat: (any TableSeat)?, newSeat: (any TableSeat)?, snapshot: TableSnapshot) {
        if player.id == tabletop.localPlayer.id, newSeat == nil {
            if isMaster {
                tabletop.claimSeat(matching: TableSeatIdentifier(0))
            } else {
                tabletop.claimAnySeat()
            }
        }
    }
}

#endif
