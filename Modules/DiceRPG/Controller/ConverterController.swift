// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    static func convert(old: DiceRPG.DiceModel) -> ItemDataCodableModel {
        let dice = old.dice_.wrappedValue.enumerated().map { (index, die) in
            DieDataModel.DieDataModelCodable(
                id: die.id,
                index: index,
                die: die.die,
                color: "",
                rotation: die.rotation,
                result: die.result
            )
        }
        let model = DiceDataModel.DiceDataModelCodable(
            itemId: old.id,
            sumUp: old.sumUp,
            modifier: old.modifier,
            percentDice: old.percentDice,
            compareOption: old.compareOption,
            compareValue: old.compareValue,
            coupValues: old.coupValues,
            coupOnlyOnFirstDie: old.coupOnlyOnFirstDie,
            fumbleValues: old.fumbleValues,
            fumbleOnlyOnFirstDie: old.fumbleOnlyOnFirstDie,
            rerollOptions: old.rerollOptions,
            reorderDice: old.reorderDice,
            addDiceEvery: old.addDiceEvery,
            dice: dice
        )
        let externalData = try? JSONEncoder().encode(model)

        let (category, tags) = convert(category: old.category_.wrappedValue, tags: old.tags_.wrappedValue, module: .dice, collection: .diceBag)
        return ItemDataCodableModel(
            id: old.id,
            module: .dice,
            name: old.name_,
            information: old.description_,
            category: category,
            tags: tags,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}
