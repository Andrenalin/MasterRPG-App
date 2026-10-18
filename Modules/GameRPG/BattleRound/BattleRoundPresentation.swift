// @copyright André Trettin

import Foundation

/// The modal Character/value list of the battle round screen, identified by
/// what it was opened for (a combatant, or a settings pattern). macOS shows
/// the same list in the window's inspector instead.
struct BattleRoundSelectionPresentation: Identifiable {
    let id: UUID
}
