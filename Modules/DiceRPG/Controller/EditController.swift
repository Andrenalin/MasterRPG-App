// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}

// MARK: - Edit dice

extension EditController {
    func add(die: DieDataModel, to model: DiceConfigDataModel) {
        let counter = model.dice.count
        let duplicate = die.duplicate(index: counter)
        model.dice.append(duplicate)
    }
    
    func remove(die: DieDataModel, from model: DiceConfigDataModel) {
        var dice = model.dice
        dice.removeAll(where: { $0.id == die.id })
        dice.enumerated().forEach { index, die in
            die.index = index
        }
        model.dice = dice
    }
    
    func add(coup: Int, isDiceValueCoup: Bool, to model: DiceConfigDataModel) {
        let newCoupOption: DiceConfigDataModel.CoupFumbleOption
        if isDiceValueCoup {
            newCoupOption = .diceValue(coup)
        } else {
            newCoupOption = .result(coup)
            if model.coupOnlyOnFirstDie {
                model.coupOnlyOnFirstDie = false
            }
        }
        model.coupValues.append(newCoupOption)
    }

    
    func remove(coup: DiceConfigDataModel.CoupFumbleOption, from model: DiceConfigDataModel) {
        model.coupValues.removeAll { $0.id == coup.id }
    }

    func add(fumble: Int, isDiceValueFumble: Bool, to model: DiceConfigDataModel) {
        let newFumbleOption: DiceConfigDataModel.CoupFumbleOption
        if isDiceValueFumble {
            newFumbleOption = .diceValue(fumble)
        } else {
            newFumbleOption = .result(fumble)
            if model.fumbleOnlyOnFirstDie {
                model.fumbleOnlyOnFirstDie = false
            }
        }
        model.fumbleValues.append(newFumbleOption)
    }

    func remove(fumble: DiceConfigDataModel.CoupFumbleOption, from model: DiceConfigDataModel) {
        model.fumbleValues.removeAll { $0.id == fumble.id }
    }

    func add(reroll: Int, value: Int, isMaxDiceValue: Bool, to model: DiceConfigDataModel) {
        let rerole = DiceConfigDataModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        model.rerollOptions.append(rerole)
    }

    func remove(reroll: DiceConfigDataModel.RerollOption, from model: DiceConfigDataModel) {
        model.rerollOptions.removeAll { $0.id == reroll.id }
    }
}
