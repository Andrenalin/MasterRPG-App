// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
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
    @MainActor func add(die: DieModel, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        editModel.dice.append(die)
        save(updated: editModel, message: String(localized: "Add \(die.name)").localizedString)
    }

    @MainActor func remove(die: DieModel, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        guard let index = editModel.dice.firstIndex(where: { $0.id == die.id }) else { return }
        editModel.dice.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove \(die.name)").localizedString)
    }

    @MainActor func add(coup: Int, isDiceValueCoup: Bool, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        let newCoupOption: DiceModel.CoupFumbleOption
        if isDiceValueCoup {
            newCoupOption = .diceValue(coup)
        } else {
            newCoupOption = .result(coup)
            if editModel.coupOnlyOnFirstDie {
                editModel.coupOnlyOnFirstDie = false
            }
        }
        editModel.coupValues.append(newCoupOption)
        save(updated: editModel, message: String(localized: "Set coup options").localizedString)
    }

    @MainActor func remove(coup: DiceModel.CoupFumbleOption, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        guard let index = editModel.coupValues.firstIndex(where: { $0 == coup }) else { return }
        editModel.coupValues.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove coup options").localizedString)
    }

    @MainActor func add(fumble: Int, isDiceValueFumble: Bool, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        let newFumbleOption: DiceModel.CoupFumbleOption
        if isDiceValueFumble {
            newFumbleOption = .diceValue(fumble)
        } else {
            newFumbleOption = .result(fumble)
            if editModel.fumbleOnlyOnFirstDie {
                editModel.fumbleOnlyOnFirstDie = false
            }
        }
        editModel.fumbleValues.append(newFumbleOption)
        save(updated: editModel, message: String(localized: "Set fumble options").localizedString)
    }

    @MainActor func remove(fumble: DiceModel.CoupFumbleOption, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        guard let index = editModel.fumbleValues.firstIndex(where: { $0 == fumble }) else { return }
        editModel.fumbleValues.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove fumble options").localizedString)
    }

    @MainActor func add(reroll: Int, value: Int, isMaxDiceValue: Bool, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        let rerole = DiceModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        editModel.rerollOptions.append(rerole)
        save(updated: editModel, message: String(localized: "Add reroll options").localizedString)
    }

    @MainActor func remove(reroll: DiceModel.RerollOption, modelId: UUID) {
        guard var editModel = editModel(for: modelId) else { return }
        guard let index = editModel.rerollOptions.firstIndex(where: { $0 == reroll }) else { return }
        editModel.rerollOptions.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove reroll options").localizedString)
    }
}
