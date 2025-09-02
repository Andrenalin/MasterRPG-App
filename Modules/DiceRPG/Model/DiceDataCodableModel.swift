// @copyright André Trettin

import Foundation

public struct DiceDataCodableModel: Equatable, Hashable, Codable, Sendable {
    init(itemId: UUID = UUID(), sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceDataModel.CompareValue = DiceDataModel.CompareValue.off, compareValue: Double = 0.0, coupValues: [DiceDataModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceDataModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceDataModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, dice: [DieDataCodableModel] = []) {
        self.itemId = itemId
        self.sumUp = sumUp
        self.modifier = modifier
        self.percentDice = percentDice
        self.compareOption = compareOption
        self.compareValue = compareValue
        self.coupValues = coupValues
        self.coupOnlyOnFirstDie = coupOnlyOnFirstDie
        self.fumbleValues = fumbleValues
        self.fumbleOnlyOnFirstDie = fumbleOnlyOnFirstDie
        self.rerollOptions = rerollOptions
        self.reorderDice = reorderDice
        self.addDiceEvery = addDiceEvery
        self.dice = dice
    }
    
    var itemId: UUID = UUID()
    
    var sumUp: Bool = true
    var modifier: Double = 0.0
    var percentDice: Bool = false
    
    // Compare
    var compareOption: DiceDataModel.CompareValue = DiceDataModel.CompareValue.off
    var compareValue: Double = 0.0

    // Coup - critical
    var coupValues: [DiceDataModel.CoupFumbleOption] = []
    var coupOnlyOnFirstDie: Bool = false
    
    // Fumble
    var fumbleValues: [DiceDataModel.CoupFumbleOption] = []
    var fumbleOnlyOnFirstDie: Bool = false
    
    // Reroll
    var rerollOptions: [DiceDataModel.RerollOption] = []

    // other option
    var reorderDice: Bool = false
    var addDiceEvery: Int = 0

    var dice: [DieDataCodableModel] = []
}

