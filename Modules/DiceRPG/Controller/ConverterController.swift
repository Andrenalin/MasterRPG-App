// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGDie
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGDie.DiceModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let dice = item.entries.enumerated().map { (index, entry) in
                let dieModel =  DieDataModel(id: entry.id, index: index, die: convertDie(die: entry.die))
                modelContext.insert(dieModel)
                return dieModel
            }
            let config = DiceDataModel(
                itemId: item.id,
                sumUp: item.sumUp,
                modifier: item.modifier,
                percentDice: item.percentDice,
                compareOption: convertCompareOption(compareOption: item.compareOption),
                compareValue: item.compareValue,
                coupValues: convertCoupFumbleValues(values: item.coupValues),
                coupOnlyOnFirstDie: item.coupOnlyOnFirstDie,
                fumbleValues: convertCoupFumbleValues(values: item.fumbleValues),
                fumbleOnlyOnFirstDie: item.fumbleOnlyOnFirstDie,
                rerollOptions: convertRerollOptions(options: item.rerollOptions),
                reorderDice: item.reorderDice,
                addDiceEvery: item.addDiceEvery,
                dice: dice
            )
            modelContext.insert(config)
            modelContext.insert(
                ItemDataModel(id: item.id, module: .dice, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, entries: [])
            )
        }
    }
        
    private static func convertDie(die: RPGDie.RawDie) -> DiceRPG.RawDie {
        switch die.sides {
        case .four: DiceRPG.RawDie.four
        case .six: DiceRPG.RawDie.six
        case .eight: DiceRPG.RawDie.eight
        case .ten: DiceRPG.RawDie.ten
        case .twelve: DiceRPG.RawDie.twelve
        case .twenty: DiceRPG.RawDie.twenty
        case .number(let int): DiceRPG.RawDie(.number(int))
        @unknown default: .twenty
        }
    }
    
    private static func convertCompareOption(compareOption: RPGDie.DiceModel.CompareValue) -> DiceDataModel.CompareValue {
        switch compareOption {
        case .off: return .off
        case .lower: return .lower
        case .lowerEqual: return .lowerEqual
        case .equalHigher: return .equalHigher
        case .higher: return .higher
        @unknown default:
            fatalError()
        }
    }
    
    private static func convertCoupFumbleValues(values: [RPGDie.DiceModel.CoupFumbleOption]) -> [DiceDataModel.CoupFumbleOption] {
        values.map { value in
            switch value {
            case .result(let n): return .result(n)
            case .diceValue(let n): return .diceValue(n)
            @unknown default:
                fatalError()
            }
        }
    }
    
    private static func convertRerollOptions(options: [RPGDie.DiceModel.RerollOption]) -> [DiceDataModel.RerollOption] {
        options.map { option in
            DiceDataModel.RerollOption(number: option.number, value: option.value, maxDiceValue: option.maxDiceValue)
        }
    }

    static func convert(old: DiceRPG.DiceModel) -> ItemDataCodableModel {
        let dice = old.dice_.wrappedValue.enumerated().map { (index, die) in
            DieDataModel.DieDataModelCodable(id: die.id, index: index, die: die.die, color: "", rotation: die.rotation, result: die.result) }
        let model = DiceDataModel.DiceDataModelCodable(itemId: old.id, sumUp: old.sumUp, modifier: old.modifier, percentDice: old.percentDice, compareOption: old.compareOption, compareValue: old.compareValue, coupValues: old.coupValues, coupOnlyOnFirstDie: old.coupOnlyOnFirstDie, fumbleValues: old.fumbleValues, fumbleOnlyOnFirstDie: old.fumbleOnlyOnFirstDie, rerollOptions: old.rerollOptions, reorderDice: old.reorderDice, addDiceEvery: old.addDiceEvery, dice: dice)
        let data = try? JSONEncoder().encode(model)

        return ItemDataCodableModel(id: old.id, module: .dice, name: old.name_, information: old.description_, category: old.category_.wrappedValue, tags: old.tags_.wrappedValue, fileUrl: nil, displayState: old.displayState, parentId: nil, entries: [], externalData: data)
    }
}
