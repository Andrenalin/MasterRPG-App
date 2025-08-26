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
            let config = DiceConfigDataModel(
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
    
    private static func convertCompareOption(compareOption: RPGDie.DiceModel.CompareValue) -> DiceConfigDataModel.CompareValue {
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
    
    private static func convertCoupFumbleValues(values: [RPGDie.DiceModel.CoupFumbleOption]) -> [DiceConfigDataModel.CoupFumbleOption] {
        values.map { value in
            switch value {
            case .result(let n): return .result(n)
            case .diceValue(let n): return .diceValue(n)
            @unknown default:
                fatalError()
            }
        }
    }
    
    private static func convertRerollOptions(options: [RPGDie.DiceModel.RerollOption]) -> [DiceConfigDataModel.RerollOption] {
        options.map { option in
            DiceConfigDataModel.RerollOption(number: option.number, value: option.value, maxDiceValue: option.maxDiceValue)
        }
    }
}
