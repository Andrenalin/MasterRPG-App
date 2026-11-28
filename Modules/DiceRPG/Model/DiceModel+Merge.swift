// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

// A plain conformance to the `@MainActor` protocol. See CODE_AUDIT_Edit_Save §4.1.
extension DiceModel: ItemDiffComparable {
    public func merge(_ other: DiceModel) -> DiceModel {
        let mergedDice = dice_.merged(other: other.dice_)
        let isLeftDice = mergedDice.update == dice_.update
        let mergedCategory = category_.merged(other: other.category_)
        return DiceModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: mergedCategory,
            // The local side's visibility, as in every other model. See CODE_AUDIT_Folder §9.8.
            displayState: other.displayState,
            dice: mergedDice,
            sumUp: isLeftDice ? sumUp : other.sumUp,
            modifier: isLeftDice ? modifier : other.modifier,
            percentDice: isLeftDice ? percentDice : other.percentDice,
            compareOption: isLeftDice ? compareOption : other.compareOption,
            compareValue: isLeftDice ? compareValue : other.compareValue,
            coupValues: isLeftDice ? coupValues : other.coupValues,
            coupOnlyOnFirstDie: isLeftDice ? coupOnlyOnFirstDie : other.coupOnlyOnFirstDie,
            fumbleValues: isLeftDice ? fumbleValues : other.fumbleValues,
            fumbleOnlyOnFirstDie: isLeftDice ? fumbleOnlyOnFirstDie : other.fumbleOnlyOnFirstDie,
            rerollOptions: isLeftDice ? rerollOptions : other.rerollOptions,
            reorderDice: isLeftDice ? reorderDice : other.reorderDice,
            addDiceEvery: isLeftDice ? addDiceEvery : other.addDiceEvery,
            // Was always `resultCategory` (self), silently discarding the
            // peer's incoming change on every merge conflict — the only
            // scalar field in this initializer that wasn't arbitrated
            // like its siblings. See CODE_AUDIT_13 §5.3.
            resultCategory: isLeftDice ? resultCategory : other.resultCategory,
            // Folders union their members, other categories last-writer-wins.
            // See CODE_AUDIT_Folder §9.8.
            entries: FolderEntryMerge.mergedEntries(category: mergedCategory.wrappedValue, local: entries_, remote: other.entries_, id: \.id, name: \.name, childId: \.childId),
            parentId: other.parentId
        )
    }

    public func isSame(_ other: DiceModel) -> Bool {
        // Split comparison into typed chunks for faster type-checking
        let basicFieldsMatch: Bool = (
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category
        )
        guard basicFieldsMatch else { return false }

        let diceConfigMatch: Bool = (
            dice_.update == other.dice_.update &&
            sumUp == other.sumUp &&
            modifier == other.modifier &&
            percentDice == other.percentDice
        )
        guard diceConfigMatch else { return false }

        let compareMatch: Bool = (
            compareOption == other.compareOption &&
            compareValue == other.compareValue
        )
        guard compareMatch else { return false }

        let specialRollsMatch: Bool = (
            coupValues == other.coupValues &&
            coupOnlyOnFirstDie == other.coupOnlyOnFirstDie &&
            fumbleValues == other.fumbleValues &&
            fumbleOnlyOnFirstDie == other.fumbleOnlyOnFirstDie &&
            rerollOptions == other.rerollOptions &&
            reorderDice == other.reorderDice &&
            addDiceEvery == other.addDiceEvery
        )
        guard specialRollsMatch else { return false }

        return resultCategory == other.resultCategory &&
               entries_.update == other.entries_.update &&
               parentId == other.parentId
    }
}

extension DiceModel: ItemDuplicatable {
    public func duplicate() -> DiceModel {
        let copyName = duplicateName(from: name)
        let dupDice = dice.map { $0.duplicate() }
        // Starts outside any folder; the duplicate flow files it. `resultCategory` is left
        // out on purpose (asserted by `DiceModelTests.assignAndDuplicate`).
        // See CODE_AUDIT_Folder §5.27.
        return DiceModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, dice: dupDice, sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, rerollOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery, entries: entries.map { $0.duplicate() }, parentId: nil)
    }
}

extension DiceModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: DiceModel, rhs: DiceModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState && lhs.resultCategory == rhs.resultCategory
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
