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
    ///   Returns whether the die was added: a set holds at most `DiceModel.maximumDecodedDiceCount`
    ///   dice (more would be cut when the set is decoded), so the bag and the intent are refused
    ///   at the limit. See CODE_AUDIT_26 §5.112.
    @discardableResult
    @MainActor func add(die: DieModel, itemId: UUID, forceSave: Bool = false) -> Bool {
        guard let editModel = editModel(for: itemId),
              editModel.dice.count < DiceModel.maximumDecodedDiceCount else { return false }
        // A die of its own: the dice bag hands out its catalog dice, and three taps on "d20" must not
        // put three dice with one id into the model. See CODE_AUDIT_26 §5.4.
        editModel.dice.append(die.duplicate())
        save(updated: editModel, message: String(localized: "Add \(die.name)", bundle: .module), forceSave: forceSave)
        return true
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
        // The option's id is its text: a second one with it would be a duplicate `ForEach` id.
        // See CODE_AUDIT_28 §5.24.
        guard !editModel[keyPath: values].contains(newOption) else { return }
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
        // A reroll is identified by its number: adding it again replaces the earlier one.
        if let index = editModel.rerollOptions.firstIndex(where: { $0.id == rerollOption.id }) {
            guard editModel.rerollOptions[index] != rerollOption else { return }
            editModel.rerollOptions[index] = rerollOption
        } else {
            editModel.rerollOptions.append(rerollOption)
        }
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
        // The modifier is a whole number everywhere it is used; a fraction is rounded here.
        // See CODE_AUDIT_26 §5.111.
        item.modifier <=> (modifier.isFinite ? modifier.rounded() : 0)
        save(updated: item, message: String(localized: "Changed modifier", bundle: .module))
    }
    
    @MainActor func reset(compareOption: DiceModel.CompareValue, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.compareOption <=> compareOption
        save(updated: item, message: String(localized: "Changed compare option", bundle: .module))
    }
}
