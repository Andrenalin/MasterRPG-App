// @copyright André Trettin

import CoreRPG
import Foundation

extension DiceModel {
    /// The editor window's forced save during a game: the dice and options it changed reach the
    /// library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: DiceModel, to edited: DiceModel) {
        if base.sumUp != edited.sumUp { sumUp = edited.sumUp }
        if base.modifier != edited.modifier { modifier = edited.modifier }
        if base.percentDice != edited.percentDice { percentDice = edited.percentDice }
        if base.compareOption != edited.compareOption { compareOption = edited.compareOption }
        if base.compareValue != edited.compareValue { compareValue = edited.compareValue }
        if base.coupValues != edited.coupValues { coupValues = edited.coupValues }
        if base.coupOnlyOnFirstDie != edited.coupOnlyOnFirstDie { coupOnlyOnFirstDie = edited.coupOnlyOnFirstDie }
        if base.fumbleValues != edited.fumbleValues { fumbleValues = edited.fumbleValues }
        if base.fumbleOnlyOnFirstDie != edited.fumbleOnlyOnFirstDie { fumbleOnlyOnFirstDie = edited.fumbleOnlyOnFirstDie }
        if base.rerollOptions != edited.rerollOptions { rerollOptions = edited.rerollOptions }
        if base.reorderDice != edited.reorderDice { reorderDice = edited.reorderDice }
        if base.addDiceEvery != edited.addDiceEvery { addDiceEvery = edited.addDiceEvery }
        // Last: `compareValue` and `addDiceEvery` reset the dice when they change.
        if base.dice != edited.dice { dice = edited.dice }
    }
}
