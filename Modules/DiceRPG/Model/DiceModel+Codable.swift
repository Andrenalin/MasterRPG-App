// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

extension DiceModel {
    /// Largest magnitude accepted for a decoded modifier or compare value (`DiceValueLimit`, shared
    /// with the Quick Dice slots). Non-finite values become 0. See CODE_AUDIT_16 §5.4.
    nonisolated static let maximumValueMagnitude = Double(DiceValueLimit.maximumMagnitude)

    nonisolated static func boundedValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -maximumValueMagnitude), maximumValueMagnitude)
    }

    /// Most dice a compare value can add. See CODE_AUDIT_16 §5.4.
    nonisolated static let maximumDiceCount = 100

    /// Bounds for a decoded set (peer package, `.gmz` import): a roll allocates and animates every
    /// die, and each option list is scanned per roll. See CODE_AUDIT_23 §5.20.
    nonisolated static let maximumDecodedDiceCount = 1_000
    nonisolated static let maximumDecodedOptionCount = 100

    nonisolated static func bounded(dice: CRDTDataUpdate<[DieModel]>) -> CRDTDataUpdate<[DieModel]> {
        guard dice.wrappedValue.count > maximumDecodedDiceCount else { return dice }
        return CRDTDataUpdate(wrappedValue: Array(dice.wrappedValue.prefix(maximumDecodedDiceCount)), update: dice.$update)
    }

    nonisolated static func bounded<Element>(options: [Element]) -> [Element] {
        options.count > maximumDecodedOptionCount ? Array(options.prefix(maximumDecodedOptionCount)) : options
    }

    nonisolated static func boundedDiceEvery(_ value: Int) -> Int {
        min(max(value, 0), DiceValueLimit.maximumMagnitude)
    }
}

extension DiceModel: nonisolated Codable {
    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _dice_
        case _sumUp
        case _modifier
        case _percentDice
        case _compareOption
        case _compareValue
        case _coupValues
        case _coupOnlyOnFirstDie
        case _fumbleValues
        case _fumbleOnlyOnFirstDie
        case _rerollOptions
        case _reorderDice
        case _addDiceEvery
        case _resultCategory
        case _entries_
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<DiceModel.CodingKeys> = encoder.container(keyedBy: DiceModel.CodingKeys.self)

            try container.encode(self.id, forKey: DiceModel.CodingKeys._id)
            try container.encode(self.name_, forKey: DiceModel.CodingKeys._name_)
            try container.encode(self.description_, forKey: DiceModel.CodingKeys._description_)
            try container.encode(self.tags_, forKey: DiceModel.CodingKeys._tags_)
            try container.encode(self.category_, forKey: DiceModel.CodingKeys._category_)
            try container.encode(self.displayState, forKey: DiceModel.CodingKeys._displayState)
            try container.encode(self.dice_, forKey: DiceModel.CodingKeys._dice_)
            try container.encode(self.sumUp, forKey: DiceModel.CodingKeys._sumUp)
            try container.encode(self.modifier, forKey: DiceModel.CodingKeys._modifier)
            try container.encode(self.percentDice, forKey: DiceModel.CodingKeys._percentDice)
            try container.encode(self.compareOption, forKey: DiceModel.CodingKeys._compareOption)
            try container.encode(self.compareValue, forKey: DiceModel.CodingKeys._compareValue)
            try container.encode(self.coupValues, forKey: DiceModel.CodingKeys._coupValues)
            try container.encode(self.coupOnlyOnFirstDie, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
            try container.encode(self.fumbleValues, forKey: DiceModel.CodingKeys._fumbleValues)
            try container.encode(self.fumbleOnlyOnFirstDie, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
            try container.encode(self.rerollOptions, forKey: DiceModel.CodingKeys._rerollOptions)
            try container.encode(self.reorderDice, forKey: DiceModel.CodingKeys._reorderDice)
            try container.encode(self.addDiceEvery, forKey: DiceModel.CodingKeys._addDiceEvery)
            try container.encodeIfPresent(self.resultCategory, forKey: DiceModel.CodingKeys._resultCategory)
            try container.encode(self.entries_, forKey: DiceModel.CodingKeys._entries_)
            try container.encodeIfPresent(self.parentId, forKey: DiceModel.CodingKeys._parentId)
    
        }
    }
}
