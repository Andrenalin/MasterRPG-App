// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
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
    @MainActor func add(die: DieModel, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.dice.append(die)
        save(updated: editModel, message: String(localized: "Add \(die.name)").localizedString)
    }

    @MainActor func remove(die: DieModel, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.dice.firstIndex(where: { $0.id == die.id }) else { return }
        editModel.dice.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove \(die.name)").localizedString)
    }

    @MainActor func add(coup: Int, isDiceValueCoup: Bool, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
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

    @MainActor func remove(coup: DiceModel.CoupFumbleOption, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.coupValues.firstIndex(where: { $0 == coup }) else { return }
        editModel.coupValues.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove coup options").localizedString)
    }

    @MainActor func add(fumble: Int, isDiceValueFumble: Bool, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
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

    @MainActor func remove(fumble: DiceModel.CoupFumbleOption, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.fumbleValues.firstIndex(where: { $0 == fumble }) else { return }
        editModel.fumbleValues.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove fumble options").localizedString)
    }

    @MainActor func add(reroll: Int, value: Int, isMaxDiceValue: Bool, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let rerole = DiceModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        editModel.rerollOptions.append(rerole)
        save(updated: editModel, message: String(localized: "Add reroll options").localizedString)
    }

    @MainActor func remove(reroll: DiceModel.RerollOption, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.rerollOptions.firstIndex(where: { $0 == reroll }) else { return }
        editModel.rerollOptions.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove reroll options").localizedString)
    }
}

extension EditController {
    @MainActor func reset(addValue: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.addDiceEvery <=> Int(addValue)
        save(updated: item, message: String(localized: "Changed add dice value").localizedString)
    }
    
    @MainActor func reset(compareValue: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.compareValue <=> compareValue
        save(updated: item, message: String(localized: "Changed compare value").localizedString)
    }
    
    @MainActor func reset(modifer: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.modifier <=> modifer
        save(updated: item, message: String(localized: "Changed modifier").localizedString)
    }
    
    @MainActor func reset(compareOption: DiceModel.CompareValue, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.compareOption <=> compareOption
        save(updated: item, message: String(localized: "Changed compare option").localizedString)
    }
}
