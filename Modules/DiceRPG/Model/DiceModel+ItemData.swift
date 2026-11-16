// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

// MARK: - Review Properties

extension DiceModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Dice", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.dice.count ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Sum Up", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.sumUp ?? true) },
            ReviewCustomProperty(displayName: String(localized: "Modifier", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.modifier ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Percent Dice", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.percentDice ?? false) },
            ReviewCustomProperty(displayName: String(localized: "Compare", bundle: .module)) { .option(($0 as? DiceModel)?.compareOption.rawText ?? "Off") },
            ReviewCustomProperty(displayName: String(localized: "Compare Value", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.compareValue ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Reorder Dice", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.reorderDice ?? false) },
            ReviewCustomProperty(displayName: String(localized: "Add Dice Every", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.addDiceEvery ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Rerolls", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.rerollOptions.count ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Coup Values", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.coupValues.count ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Fumble Values", bundle: .module)) { ReviewPropertyValue(($0 as? DiceModel)?.fumbleValues.count ?? 0) }
        ]
    }
}

// The `ItemDataAccessible` conformance is declared in DiceModel.swift: it implies `Sendable`, which
// must be stated in the file of the class.
extension DiceModel {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }
    
    nonisolated public static var empty: DiceModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> DiceModel {
        DiceModel(id: id, name: "", dice: [])
    }
    nonisolated public static let typeId: NetworkModules = .dice

    public func copy() -> DiceModel {
        copy(withId: id)
    }

    /// Clone with a different identity — `id` is immutable (nonisolated Identifiable),
    /// so game flows that rebrand a dice make a fresh copy instead of mutating.
    public func copy(withId newId: UUID) -> DiceModel {
        DiceModel(id: newId, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, dice: dice_, sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, rerollOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery, resultCategory: resultCategory, entries: entries_, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        return false
    }

    public func isEqual(other: DiceModel) -> Bool {
        self == other
    }

    public var isGroupHiddenToggle: Bool {
        get { isGroupHidden }
        set {
            if newValue {
                displayState = DisplayStateMask.groupHidden.set(on: displayState)
            } else {
                displayState = DisplayStateMask.groupHidden.reset(on: displayState)
            }
        }
    }

    @MainActor public func replace(with model: DiceModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        dice_ = model.dice_
        sumUp <=> model.sumUp
        modifier <=> model.modifier
        percentDice <=> model.percentDice
        compareOption <=> model.compareOption
        compareValue <=> model.compareValue
        coupValues <=> model.coupValues
        coupOnlyOnFirstDie <=> model.coupOnlyOnFirstDie
        fumbleValues <=> model.fumbleValues
        fumbleOnlyOnFirstDie <=> model.fumbleOnlyOnFirstDie
        rerollOptions <=> model.rerollOptions
        reorderDice <=> model.reorderDice
        addDiceEvery <=> model.addDiceEvery
        resultCategory <=> model.resultCategory
        entries_ <=> model.entries_
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> ChildEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return ChildEntryModel.empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }

    public func die(for id: UUID) -> DieModel {
        guard let index = dice.firstIndex(where: { $0.id == id }) else { return .empty(id) }
        return dice[index]
    }
    
    public func resetDie(_ die: DieModel) {
        guard let index = dice.firstIndex(where: { $0.id == die.id }) else { return }
        dice[index] = die
    }

    public func urlName() -> String {
        inlineText
    }

    public func urlName(entryId: UUID) -> String {
        inlineText
    }

    public func url(linkNumber: Int, entryId: UUID) -> String {
        url(linkNumber: linkNumber)
    }
}
