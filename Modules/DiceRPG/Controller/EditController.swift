// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = DiceModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
}

extension EditController {
    @MainActor func add(die: DieModel) {
        model.dice.append(die)
        save(with: String(localized: "Add \(die.name)").localizedString)
    }

    @MainActor func remove(die: DieModel) {
        guard let index = model.dice.firstIndex(where: { $0.id == die.id }) else { return }
        model.dice.remove(at: index)
        save(with: String(localized: "Remove \(die.name)").localizedString)
    }

    @MainActor func add(coup: Int, isDiceValueCoup: Bool) {
        let newCoupOption: DiceModel.CoupFumbleOption
        if isDiceValueCoup {
            newCoupOption = .diceValue(coup)
        } else {
            newCoupOption = .result(coup)
            if model.coupOnlyOnFirstDie {
                model.coupOnlyOnFirstDie = false
            }
        }
        model.coupValues.append(newCoupOption)
        save(with: String(localized: "Set coup options").localizedString)
    }

    @MainActor func remove(coup: DiceModel.CoupFumbleOption) {
        guard let index = model.coupValues.firstIndex(where: { $0 == coup }) else { return }
        model.coupValues.remove(at: index)
        save(with: String(localized: "Remove coup options").localizedString)
    }

    @MainActor func add(fumble: Int, isDiceValueFumble: Bool) {
        let newFumbleOption: DiceModel.CoupFumbleOption
        if isDiceValueFumble {
            newFumbleOption = .diceValue(fumble)
        } else {
            newFumbleOption = .result(fumble)
            if model.fumbleOnlyOnFirstDie {
                model.fumbleOnlyOnFirstDie = false
            }
        }
        model.fumbleValues.append(newFumbleOption)
        save(with: String(localized: "Set fumble options").localizedString)
    }

    @MainActor func remove(fumble: DiceModel.CoupFumbleOption) {
        guard let index = model.fumbleValues.firstIndex(where: { $0 == fumble }) else { return }
        model.fumbleValues.remove(at: index)
        save(with: String(localized: "Remove fumble options").localizedString)
    }

    @MainActor func add(reroll: Int, value: Int, isMaxDiceValue: Bool) {
        let rerole = DiceModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        model.rerollOptions.append(rerole)
        save(with: String(localized: "Add reroll options").localizedString)
    }

    @MainActor func remove(reroll: DiceModel.RerollOption) {
        guard let index = model.rerollOptions.firstIndex(where: { $0 == reroll }) else { return }
        model.rerollOptions.remove(at: index)
        save(with: String(localized: "Remove reroll options").localizedString)
    }
}
