// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// See CODE_AUDIT_EditItem §9.1 — genericized in `GenericEditController` (CoreRPG);
/// this module has no extra stored state beyond the generic default.
typealias EditController = GenericEditController<DiceModel>

extension EditController {
    /// - Parameter forceSave: `true` adds the die to the library dice also during a game (the
    ///   Add Die intent). See CODE_AUDIT_Since_3.0.1 §5.2.
    @MainActor func add(die: DieModel, itemId: UUID, forceSave: Bool = false) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.dice.append(die)
        save(updated: editModel, message: String(localized: "Add \(die.name)", bundle: .module), forceSave: forceSave)
    }

    @MainActor func remove(die: DieModel, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard let index = item.dice.firstIndex(where: { $0.id == die.id }) else { return }
        item.dice.remove(at: index)
        save(updated: item, message: String(localized: "Remove \(die.name)", bundle: .module))
    }

    @MainActor func add(coup: Int, isDiceValueCoup: Bool, itemId: UUID) {
        addSpecialValue(coup, isDiceValue: isDiceValueCoup, itemId: itemId, values: \.coupValues, onlyOnFirstDie: \.coupOnlyOnFirstDie, message: String(localized: "Set coup options", bundle: .module))
    }

    @MainActor func remove(coup: DiceModel.CoupFumbleOption, itemId: UUID) {
        removeSpecialValue(coup, itemId: itemId, values: \.coupValues, message: String(localized: "Remove coup options", bundle: .module))
    }

    @MainActor func add(fumble: Int, isDiceValueFumble: Bool, itemId: UUID) {
        addSpecialValue(fumble, isDiceValue: isDiceValueFumble, itemId: itemId, values: \.fumbleValues, onlyOnFirstDie: \.fumbleOnlyOnFirstDie, message: String(localized: "Set fumble options", bundle: .module))
    }

    @MainActor func remove(fumble: DiceModel.CoupFumbleOption, itemId: UUID) {
        removeSpecialValue(fumble, itemId: itemId, values: \.fumbleValues, message: String(localized: "Remove fumble options", bundle: .module))
    }

    // Coup and fumble were structurally identical add/remove pairs, differing
    // only in which stored property they touched. See CODE_AUDIT §9.3.
    @MainActor
    private func addSpecialValue(_ value: Int, isDiceValue: Bool, itemId: UUID, values: ReferenceWritableKeyPath<DiceModel, [DiceModel.CoupFumbleOption]>, onlyOnFirstDie: ReferenceWritableKeyPath<DiceModel, Bool>, message: String) {
        guard let editModel = editModel(for: itemId) else { return }
        let newOption: DiceModel.CoupFumbleOption
        if isDiceValue {
            newOption = .diceValue(value)
        } else {
            newOption = .result(value)
            if editModel[keyPath: onlyOnFirstDie] {
                editModel[keyPath: onlyOnFirstDie] = false
            }
        }
        editModel[keyPath: values].append(newOption)
        save(updated: editModel, message: message)
    }

    @MainActor
    private func removeSpecialValue(_ value: DiceModel.CoupFumbleOption, itemId: UUID, values: ReferenceWritableKeyPath<DiceModel, [DiceModel.CoupFumbleOption]>, message: String) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel[keyPath: values].firstIndex(where: { $0 == value }) else { return }
        editModel[keyPath: values].remove(at: index)
        save(updated: editModel, message: message)
    }

    @MainActor func add(reroll: Int, value: Int, isMaxDiceValue: Bool, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let rerollOption = DiceModel.RerollOption(number: reroll, value: value, maxDiceValue: isMaxDiceValue)
        editModel.rerollOptions.append(rerollOption)
        save(updated: editModel, message: String(localized: "Add reroll options", bundle: .module))
    }

    @MainActor func remove(reroll: DiceModel.RerollOption, itemId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        guard let index = editModel.rerollOptions.firstIndex(where: { $0 == reroll }) else { return }
        editModel.rerollOptions.remove(at: index)
        save(updated: editModel, message: String(localized: "Remove reroll options", bundle: .module))
    }
}

extension EditController {
    @MainActor func reset(addValue: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.addDiceEvery <=> Int(addValue)
        save(updated: item, message: String(localized: "Changed add dice value", bundle: .module))
    }
    
    @MainActor func reset(compareValue: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.compareValue <=> compareValue
        save(updated: item, message: String(localized: "Changed compare value", bundle: .module))
    }
    
    @MainActor func reset(modifier: Double, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.modifier <=> modifier
        save(updated: item, message: String(localized: "Changed modifier", bundle: .module))
    }
    
    @MainActor func reset(compareOption: DiceModel.CompareValue, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.compareOption <=> compareOption
        save(updated: item, message: String(localized: "Changed compare option", bundle: .module))
    }
}
