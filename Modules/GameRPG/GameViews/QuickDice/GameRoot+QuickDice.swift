// @copyright André Trettin

import CoreRPG
import Foundation

extension GameRoot {
    /// Whether a screen offers the quick dice overlay and its toggle, by the rule in
    /// `QuickDiceSlotsModel.isOffered(isMaster:gameType:)`.
    @MainActor
    func offersQuickDice(isMaster: Bool) -> Bool {
        QuickDiceSlotsModel.isOffered(isMaster: isMaster, gameType: gameModel.gameType)
    }
}
