// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController? = nil
    
    var itemControllable: any ItemControllable {
        itemController
    }
}

extension EditController: EditControllable {
    func delete(item: ItemDataModel) {
        // First delete the associated DiceDataModel
        deleteDiceDataModel(for: item.id)
        
        // Then delete the ItemDataModel using the default implementation
        deleteDataModel(item: item)
    }
    
    @MainActor 
    private func deleteDiceDataModel(for itemId: UUID) {
        // Use ItemController to get the DiceDataModel
        guard let diceModel = itemController.model(for: itemId) else { return }
        
        // Delete the DiceDataModel using its modelContext
        guard let modelContext = diceModel.modelContext else { return }
        modelContext.delete(diceModel)
        try? modelContext.save()
    }
}

// MARK: - Edit dice

extension EditController {
    func add(die: DieDataModel, to model: DiceDataModel) {
        let counter = model.dice.count
        let duplicate = die.duplicate(index: counter)
        model.dice.append(duplicate)
        try? model.modelContext?.save()
    }
    
    func remove(die: DieDataModel, from model: DiceDataModel) {
        var dice = model.dice
        dice.removeAll(where: { $0.id == die.id })
        dice.enumerated().forEach { index, die in
            die.index = index
        }
        model.dice = dice
    }
    
    func add(coup: Int, isDiceValueCoup: Bool, to model: DiceDataModel) {
        let newCoupOption: DiceDataModel.CoupFumbleOption
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

    
    func remove(coup: DiceDataModel.CoupFumbleOption, from model: DiceDataModel) {
        model.coupValues.removeAll { $0.id == coup.id }
    }

    func add(fumble: Int, isDiceValueFumble: Bool, to model: DiceDataModel) {
        let newFumbleOption: DiceDataModel.CoupFumbleOption
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

    func remove(fumble: DiceDataModel.CoupFumbleOption, from model: DiceDataModel) {
        model.fumbleValues.removeAll { $0.id == fumble.id }
    }

    func add(reroll: Int, value: Int, isMaxDiceValue: Bool, to model: DiceDataModel) {
        let rerole = DiceDataModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        model.rerollOptions.append(rerole)
    }

    func remove(reroll: DiceDataModel.RerollOption, from model: DiceDataModel) {
        model.rerollOptions.removeAll { $0.id == reroll.id }
    }
}
