// @copyright André Trettin

import CoreRPG
import Foundation

extension GameRoot {
    /// Whether a screen offers the quick dice overlay and its toggle: to a player who plays, not
    /// to the game master and not to an observer.
    @MainActor
    func offersQuickDice(isMaster: Bool) -> Bool {
        !isMaster && gameModel.gameType != .observer
    }
}
