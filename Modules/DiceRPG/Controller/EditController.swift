// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    let fileUrlDataController: FileUrlDataController? = nil
}

extension EditController: EditControllable {
    typealias Model = DiceDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    func createNewEntry(in model: DiceDataModel, childId: UUID) -> DiceEntryDataModel {
        DiceEntryDataModel(id: UUID(), index: model.entries.count, parentId: model.id, childId: childId, item: model)
    }
    
    func duplicate(model: DiceDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await actor.duplicate(url: nil)
            await actor.save()
        }
    }
}

// MARK: - Edit dice

extension EditController {
    func add(die: DieDataModel, to model: DiceDataModel) {
        let counter = model.config.dice.count
        let duplicate = die.duplicate(index: counter)
        let config = model.config
        config.dice.append(duplicate)
        model.config = config
    }
    
    func remove(die: DieDataModel, from model: DiceDataModel) {
        let config = model.config
        var dice = config.dice
        dice.removeAll(where: { $0.id == die.id })
        dice.enumerated().forEach { index, die in
            die.index = index
        }
        config.dice = dice
        model.config = config
    }
    
    func add(coup: Int, isDiceValueCoup: Bool, to model: DiceDataModel) {
        let config = model.config
        let newCoupOption: DiceConfigDataModel.CoupFumbleOption
        if isDiceValueCoup {
            newCoupOption = .diceValue(coup)
        } else {
            newCoupOption = .result(coup)
            if config.coupOnlyOnFirstDie {
                config.coupOnlyOnFirstDie = false
            }
        }
        config.coupValues.append(newCoupOption)
        model.config = config
    }

    
    func remove(coup: DiceConfigDataModel.CoupFumbleOption, from model: DiceDataModel) {
        let config = model.config
        config.coupValues.removeAll { $0.id == coup.id }
        model.config = config
    }

    func add(fumble: Int, isDiceValueFumble: Bool, to model: DiceDataModel) {
        let config = model.config
        let newFumbleOption: DiceConfigDataModel.CoupFumbleOption
        if isDiceValueFumble {
            newFumbleOption = .diceValue(fumble)
        } else {
            newFumbleOption = .result(fumble)
            if config.fumbleOnlyOnFirstDie {
                config.fumbleOnlyOnFirstDie = false
            }
        }
        config.fumbleValues.append(newFumbleOption)
        model.config = config
    }

    func remove(fumble: DiceConfigDataModel.CoupFumbleOption, from model: DiceDataModel) {
        let config = model.config
        config.fumbleValues.removeAll { $0.id == fumble.id }
        model.config = config
    }

    func add(reroll: Int, value: Int, isMaxDiceValue: Bool, to model: DiceDataModel) {
        let config = model.config
        let rerole = DiceConfigDataModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        config.rerollOptions.append(rerole)
        model.config = config
    }

    func remove(reroll: DiceConfigDataModel.RerollOption, from model: DiceDataModel) {
        let config = model.config
        config.rerollOptions.removeAll { $0.id == reroll.id }
        model.config = config
    }

}
