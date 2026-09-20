// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

/// The leading ornament's window-controls row entry (alongside `GameTableSideMenu`): toggles the
/// floating adventure (master) or character sheet (player) window. It mirrors `GameTableSideMenu`'s
/// gating exactly: the master needs an `adventureId` before it can show; a player needs an active
/// (non-observer) game. A separate `View` struct rather than a computed property on `GameTableView`
/// so it gets its own invalidation boundary.
@MainActor
struct WindowOpenButton: View {
    let root: GameRoot

    var body: some View {
        if root.gameModel.gameConfig.isMaster {
            if let adventureId = root.gameModel.gameConfig.master.adventureId {
                GameWindowMenuButtonView(isMaster: true, itemId: adventureId)
            }
        } else if root.gameModel.gameType != .observer {
            GameWindowMenuButtonView(isMaster: false, itemId: root.gameModel.selectedCharacter)
        }
    }
}
#endif
