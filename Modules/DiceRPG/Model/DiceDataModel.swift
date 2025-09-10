// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import SwiftUI

@Model 
public final class DiceDataModel {
    init(itemId: UUID = UUID(), sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceDataModel.CompareValue = DiceDataModel.CompareValue.off, compareValue: Double = 0.0, coupValues: [DiceDataModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceDataModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceDataModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, dice: [DieDataModel] = [], resultCategory: ResultCategory? = nil) {
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
        self.dice_ = dice
    }
    
    var itemId: UUID = UUID()
    
    var sumUp: Bool = true
    var modifier: Double = 0.0
    var percentDice: Bool = false
    
    // Compare
    var compareOption: CompareValue = DiceDataModel.CompareValue.off
    var compareValue: Double = 0.0 {
        didSet {
            resetDice()
        }
    }
    
    // Coup - critical
    var coupValues: [CoupFumbleOption] = []
    var coupOnlyOnFirstDie: Bool = false
    
    // Fumble
    var fumbleValues: [CoupFumbleOption] = []
    var fumbleOnlyOnFirstDie: Bool = false
    
    // Reroll
    var rerollOptions: [RerollOption] = []
    
    // other option
    var reorderDice: Bool = false
    var addDiceEvery: Int = 0 {
        didSet {
            resetDice()
        }
    }
    
    @Relationship(deleteRule: .cascade) private var dice_: [DieDataModel]? = []

    @Transient
    var resultCategory: ResultCategory? = nil
    
    // MARK: Codable
    
    struct DiceDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: CompareValue = DiceDataModel.CompareValue.off, compareValue: Double = 0.0 , coupValues: [CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0 , dice: [DieDataModel.DieDataModelCodable] = [], resultCategory: ResultCategory? = nil) {
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
            self.resultCategory = resultCategory
        }
        var itemId: UUID = UUID()
        var sumUp: Bool = true
        var modifier: Double = 0.0
        var percentDice: Bool = false
        var compareOption: CompareValue = DiceDataModel.CompareValue.off
        var compareValue: Double = 0.0
        var coupValues: [CoupFumbleOption] = []
        var coupOnlyOnFirstDie: Bool = false
        var fumbleValues: [CoupFumbleOption] = []
        var fumbleOnlyOnFirstDie: Bool = false
        var rerollOptions: [RerollOption] = []
        var reorderDice: Bool = false
        var addDiceEvery: Int = 0
        var dice: [DieDataModel.DieDataModelCodable] = []
        var resultCategory: ResultCategory? = nil
    }
    
    convenience init(_ model: DiceDataModelCodable) {
        self.init(itemId: model.itemId, sumUp: model.sumUp, modifier: model.modifier, percentDice: model.percentDice, compareOption: model.compareOption, compareValue: model.compareValue, coupValues: model.coupValues, coupOnlyOnFirstDie: model.coupOnlyOnFirstDie, fumbleValues: model.fumbleValues, fumbleOnlyOnFirstDie: model.fumbleOnlyOnFirstDie, rerollOptions: model.rerollOptions, reorderDice: model.reorderDice, addDiceEvery: model.addDiceEvery, dice: [], resultCategory: model.resultCategory)
        self.dice = model.dice.map { DieDataModel($0) }
    }
    
    var codableModel: DiceDataModelCodable {
        DiceDataModelCodable(
            itemId: itemId,
            sumUp: sumUp,
            modifier: modifier,
            percentDice: percentDice,
            compareOption: compareOption,
            compareValue: compareValue,
            coupValues: coupValues,
            coupOnlyOnFirstDie: coupOnlyOnFirstDie,
            fumbleValues: fumbleValues,
            fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie,
            rerollOptions: rerollOptions,
            reorderDice: reorderDice,
            addDiceEvery: addDiceEvery,
            dice: dice.map {
                $0.codableModel
            },
            resultCategory: resultCategory
        )
    }
    
    func replace(_ model: DiceDataModelCodable) {
        itemId = model.itemId
        sumUp = model.sumUp
        modifier = model.modifier
        percentDice = model.percentDice
        compareOption = model.compareOption
        compareValue = model.compareValue
        coupValues = model.coupValues
        coupOnlyOnFirstDie = model.coupOnlyOnFirstDie
        fumbleValues = model.fumbleValues
        fumbleOnlyOnFirstDie = model.fumbleOnlyOnFirstDie
        rerollOptions = model.rerollOptions
        reorderDice = model.reorderDice
        addDiceEvery = model.addDiceEvery
        dice = model.dice.map { DieDataModel($0) }
        resultCategory = model.resultCategory
    }
}

extension DiceDataModel {
    var dice: [DieDataModel] {
        get {
            guard let all = dice_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            dice_ = newValue
        }
    }

    static var twenty: DiceDataModel {
        DiceDataModel(dice: [DieDataModel.die20])
    }    
}

extension DiceDataModel {
    var addDiceActivate: Bool {
        get { addDiceEvery > 0 }
        set { reset(addDice: newValue) }
    }
    
    func reset(addDice: Bool) {
        if addDice {
            let newMax = dice.first?.die.max ?? 0
            addDiceEvery = newMax
        } else {
            addDiceEvery = 0
        }
    }
    var canFumbleOnFirstDiceOnly: Bool {
        guard !fumbleValues.contains(where: { $0.isResult }) else { return false }
        return fumbleOnlyOnFirstDie
    }
    
    var canCoupOnFirstDiceOnly: Bool {
        guard !coupValues.contains(where: { $0.isResult }) else { return false }
        return coupOnlyOnFirstDie
    }
    
    var canPercentDice: Bool {
        guard dice.count == 2 else { return false }
        return dice[0].die.sides == .ten && dice[1].die.sides == .ten
    }
    
    var inlineText: String {
        var diceModel = RawDice(dice: dice.map { $0.die })
        diceModel.modifier = Int(modifier)
        return diceModel.text
    }
    
    func resetDice() {
        guard addDiceEvery > 0 else { return }
        var number = Int(compareValue) / addDiceEvery + (Int(compareValue) % addDiceEvery > 0 ? 1 : 0)
        if number <= 0 {
            number = 1
        }
        if dice.count != number, let die = dice.first {
            dice = (1 ... number).map { die.duplicate(index: $0 - 1) }
        }
    }
    
    func applyResult(text: String) {
        let diceResult = text.split(separator: "|")
        guard diceResult.count == dice.count else { return }
        for index in 0 ..< dice.count {
            let dieResult = diceResult[index]
                .split(separator: ",", omittingEmptySubsequences: false)
                .compactMap { Int($0) }
            dice[index].applyResult(values: dieResult)
        }
    }
    
    var minValue: Int {
        dice.reduce(0) { $0 + $1.die.min }
    }
    
    var maxValue: Int {
        dice.reduce(0) { $0 + $1.die.max }
    }
}

extension DiceDataModel {
    enum CompareValue: Int, Identifiable, Equatable, Hashable, Codable, CaseIterable {
        case off
        case lower
        case lowerEqual
        case equalHigher
        case higher
        
        public var id: Int {
            rawValue
        }
        
        var text: LocalizedStringKey {
            switch self {
            case .off: "Off"
            case .lower: "<"
            case .lowerEqual: "<="
            case .equalHigher: ">="
            case .higher: ">"
            }
        }
        
        var rawText: String {
            switch self {
            case .off: "Off"
            case .lower: "<"
            case .lowerEqual: "<="
            case .equalHigher: ">="
            case .higher: ">"
            }
        }
        
        var icon: String {
            switch self {
            case .off: ""
            case .lower: "lessthan.circle"
            case .lowerEqual: "arrow.left.to.line.circle"
            case .equalHigher: "arrow.right.to.line.circle"
            case .higher: "greaterthan.circle"
            }
        }
        
        func check(value: Double, against other: Double) -> Bool {
            switch self {
            case .off: false
            case .lower: value < other
            case .lowerEqual: value <= other
            case .equalHigher: value >= other
            case .higher: value > other
            }
        }
    }
}

extension DiceDataModel {
    enum CoupFumbleOption: Identifiable, Equatable, Hashable, Codable, RawRepresentable {
        case result(Int)
        case diceValue(Int)
        
        public init?(rawValue: String) {
            guard rawValue.count > 1 else { return nil }
            let index = rawValue.index(after: rawValue.startIndex)
            let number = Int(rawValue[index...]) ?? 0
            if rawValue[rawValue.startIndex] == "r" {
                self = .result(number)
            } else if rawValue[rawValue.startIndex] == "d" {
                self = .diceValue(number)
            } else {
                return nil
            }
        }
        
        public var rawValue: String {
            switch self {
            case let .result(number): "r\(number)"
            case let .diceValue(number): "d\(number)"
            }
        }
        
        public var id: String {
            rawValue
        }
        
        var icon: String {
            switch self {
            case .diceValue: NetworkModules.dice.icon
            case .result: "123.rectangle"
            }
        }
        
        var text: String {
            switch self {
            case let .diceValue(number): "\(number)"
            case let .result(number): "\(number)"
            }
        }
        
        func isDiceValue(_ value: Int) -> Bool {
            switch self {
            case let .diceValue(number): number == value
            case .result: false
            }
        }
        
        func isResultValue(_ value: Int) -> Bool {
            switch self {
            case .diceValue: false
            case let .result(number): number == value
            }
        }
        
        var isResult: Bool {
            switch self {
            case .result: true
            default: false
            }
        }
    }
    
}

extension DiceDataModel {
    struct RerollOption: Identifiable, Equatable, Hashable, Codable {
        let number: Int
        let value: Int
        let maxDiceValue: Bool
        
        public var id: Int {
            number
        }
    }
}
