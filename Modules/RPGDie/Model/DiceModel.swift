// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import SwiftUI

@Observable
public final class DiceModel: Identifiable, @unchecked Sendable {
    public init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, dice: [DieModel], sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, reroleOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil) {
        self.id = id
        name_ = CRDT(wrappedValue: name)
        description_ = CRDT(wrappedValue: description)
        tags_ = CRDT(wrappedValue: tags)
        category_ = CRDT(wrappedValue: category)
        self.displayState = displayState
        dice_ = CRDTDataUpdate(wrappedValue: dice)
        self.sumUp = sumUp
        self.modifier = modifier
        self.percentDice = percentDice
        self.compareOption = compareOption
        self.compareValue = compareValue
        self.coupValues = coupValues
        self.coupOnlyOnFirstDie = coupOnlyOnFirstDie
        self.fumbleValues = fumbleValues
        self.fumbleOnlyOnFirstDie = fumbleOnlyOnFirstDie
        self.rerollOptions = reroleOptions
        self.reorderDice = reorderDice
        self.addDiceEvery = addDiceEvery
        self.resultCategory = resultCategory
    }

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, dice: CRDTDataUpdate<[DieModel]>, sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil) {
        self.id = id
        name_ = name
        description_ = description
        tags_ = tags
        category_ = category
        self.displayState = displayState
        dice_ = dice
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
        self.resultCategory = resultCategory
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<DiceModel.CodingKeys> = try decoder.container(keyedBy: DiceModel.CodingKeys.self)

        self._id = try container.decode(UUID.self, forKey: DiceModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: DiceModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: DiceModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: DiceModel.CodingKeys._displayState)
        self._dice_ = try container.decode(CRDTDataUpdate<[DieModel]>.self, forKey: DiceModel.CodingKeys._dice_)
        self._sumUp = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._sumUp)
        self._modifier = try container.decode(Double.self, forKey: DiceModel.CodingKeys._modifier)
        self._percentDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._percentDice)
        self._compareOption = try container.decode(DiceModel.CompareValue.self, forKey: DiceModel.CodingKeys._compareOption)
        self._compareValue = try container.decode(Double.self, forKey: DiceModel.CodingKeys._compareValue)
        self._coupValues = try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._coupValues)
        self._coupOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
        self._fumbleValues = try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._fumbleValues)
        self._fumbleOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
        self._rerollOptions = try container.decode([DiceModel.RerollOption].self, forKey: DiceModel.CodingKeys._rerollOptions)
        self._reorderDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._reorderDice)
        self._addDiceEvery = try container.decode(Int.self, forKey: DiceModel.CodingKeys._addDiceEvery)
        self._resultCategory = try container.decodeIfPresent(ResultCategory.self, forKey: DiceModel.CodingKeys._resultCategory)
    }
    
    public var id: UUID
    public var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    var name_: CRDT<String>

    public var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    var description_: CRDT<String>

    public var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    var tags_: CRDT<[String]>

    public var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    var category_: CRDT<ItemListCategory>

    public var displayState: Int

    public var entries: [DieModel] {
        get { dice_.wrappedValue }
        set { dice_.wrappedValue = newValue }
    }
    var dice_: CRDTDataUpdate<[DieModel]>

    var sumUp: Bool = true
    var modifier: Double = 0.0
    var percentDice: Bool = false

    public enum CompareValue: Int, Identifiable, Equatable, Hashable, Codable, CaseIterable {
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
            case .off:
                return "Off"
            case .lower:
                return "<"
            case .lowerEqual:
                return "<="
            case .equalHigher:
                return ">="
            case .higher:
                return ">"
            }
        }

        var rawText: String {
            switch self {
            case .off:
                return "Off"
            case .lower:
                return "<"
            case .lowerEqual:
                return "<="
            case .equalHigher:
                return ">="
            case .higher:
                return ">"
            }
        }

        var icon: String {
            switch self {
            case .off:
                return ""
            case .lower:
                return "lessthan.circle"
            case .lowerEqual:
                return "arrow.left.to.line.circle"
            case .equalHigher:
                return "arrow.right.to.line.circle"
            case .higher:
                return "greaterthan.circle"
            }
        }

        func check(value: Double, against other: Double) -> Bool {
            switch self {
            case .off:
                return false
            case .lower:
                return value < other
            case .lowerEqual:
                return value <= other
            case .equalHigher:
                return value >= other
            case .higher:
                return value > other
            }
        }
    }

    var compareOption: CompareValue = .off
    var compareValue: Double = 0.0 {
        didSet {
            resetDice()
        }
    }

    public enum CoupFumbleOption: Identifiable, Equatable, Hashable, Codable, RawRepresentable {
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
            case let .result(number):
                return "r\(number)"
            case let .diceValue(number):
                return "d\(number)"
            }
        }

        public var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .diceValue:
                return NetworkModules.dice.icon
            case .result:
                return "123.rectangle"
            }
        }

        var text: String {
            switch self {
            case let .diceValue(number):
                return "\(number)"
            case let .result(number):
                return "\(number)"
            }
        }

        func isDiceValue(_ value: Int) -> Bool {
            switch self {
            case let .diceValue(number):
                return number == value
            case .result:
                return false
            }
        }

        func isResultValue(_ value: Int) -> Bool {
            switch self {
            case .diceValue:
                return false
            case let .result(number):
                return number == value
            }
        }

        var isResult: Bool {
            switch self {
            case .result:
                return true
            default:
                return false
            }
        }
    }

    var coupValues: [CoupFumbleOption] = []
    var coupOnlyOnFirstDie: Bool = false

    var fumbleValues: [CoupFumbleOption] = []
    var fumbleOnlyOnFirstDie: Bool = false

    public struct RerollOption: Identifiable, Equatable, Hashable, Codable {
        let number: Int
        let value: Int
        let maxDiceValue: Bool

        public var id: Int {
            number
        }
    }

    var rerollOptions: [RerollOption] = []

    var reorderDice: Bool = false
    var addDiceEvery: Int = 0 {
        didSet {
            resetDice()
        }
    }

    var resultCategory: ResultCategory? = nil
}

extension DiceModel {
    var canFumbleOnFirstDiceOnly: Bool {
        guard !fumbleValues.contains(where: { $0.isResult }) else { return false }
        return fumbleOnlyOnFirstDie
    }
    
    var canCoupOnFirstDiceOnly: Bool {
        guard !coupValues.contains(where: { $0.isResult }) else { return false }
        return coupOnlyOnFirstDie
    }
    
    var canPercentDice: Bool {
        guard entries.count == 2 else { return false }
        return entries[0].die.sides == .ten && entries[1].die.sides == .ten
    }
    
    var inlineText: String {
        var diceModel = RawDice(dice: entries.map { $0.die })
        diceModel.modifier = Int(modifier)
        return diceModel.text
    }
    
    func resetDice() {
        guard addDiceEvery > 0 else { return }
        var number = Int(compareValue) / addDiceEvery + (Int(compareValue) % addDiceEvery > 0 ? 1 : 0)
        if number <= 0 {
            number = 1
        }
        if entries.count != number, let die = entries.first {
            entries = (1 ... number).map { _ in die.duplicate() }
        }
    }
    
    func applyResult(text: String) {
        let diceResult = text.split(separator: "|")
        guard diceResult.count == entries.count else { return }
        for index in 0 ..< entries.count {
            let dieResult = diceResult[index]
                .split(separator: ",", omittingEmptySubsequences: false)
                .compactMap { Int($0) }
            let die = entries[index].applyResult(values: dieResult)
            entries[index] = die
        }
    }
    
    var minValue: Int {
        entries.reduce(0) { $0 + $1.die.min }
    }
    
    var maxValue: Int {
        entries.reduce(0) { $0 + $1.die.max }
    }
}

extension DiceModel: Comparable {
    public static func < (lhs: DiceModel, rhs: DiceModel) -> Bool {
        lhs.name < rhs.name
    }
}

extension DiceModel: ItemLinkRegistable {}

extension DiceModel: ItemDiffComparable {
    public func merge(_ other: DiceModel) -> DiceModel {
        let mergedDice = dice_.merged(other: other.dice_)
        let isLeftDice = mergedDice.update == dice_.update
        return DiceModel(
            id: id,
            name: name_.merged(other: other.name_),
            description: description_.merged(other: other.description_),
            tags: tags_.merged(other: other.tags_),
            category: category_.merged(other: other.category_),
            displayState: displayState,
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
            resultCategory: resultCategory
        )
    }

    public func isSame(_ other: DiceModel) -> Bool {
        name == other.name &&
        description == other.description &&
        tags == other.tags &&
        category == other.category &&
        dice_.update == other.dice_.update &&
        sumUp == other.sumUp &&
        modifier == other.modifier &&
        percentDice == other.percentDice &&
        compareOption == other.compareOption &&
        compareValue == other.compareValue &&
        coupValues == other.coupValues &&
        coupOnlyOnFirstDie == other.coupOnlyOnFirstDie &&
        fumbleValues == other.fumbleValues &&
        fumbleOnlyOnFirstDie == other.fumbleOnlyOnFirstDie &&
        rerollOptions == other.rerollOptions &&
        reorderDice == other.reorderDice &&
        addDiceEvery == other.addDiceEvery &&
        resultCategory == other.resultCategory
    }
}

extension DiceModel: ItemDuplicatable {
    public func duplicate() -> DiceModel {
        let copyName = duplicateName(from: name)
        let dupDice = entries.map { dieVM -> DieModel in
            DieModel(id: UUID(), die: dieVM.die)
        }
        return DiceModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, dice: dupDice, sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, reroleOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery)
    }
}

extension DiceModel: ItemDataAccessable {
    public static var empty: DiceModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> DiceModel {
        DiceModel(id: id, name: "", dice: [])
    }
    public static let typeId: NetworkModules = .dice

    public func copy() -> DiceModel {
        DiceModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, dice: dice_, sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, rerollOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery, resultCategory: resultCategory)
    }

    public func filter(_ filter: String) -> Bool {
        (filter.isEmpty || name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter))
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

    public func replace(with model: DiceModel) -> Bool {
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
        return true
    }

    public subscript(id: UUID) -> DieModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
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

extension DiceModel: Codable {
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
    }

    public final func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<DiceModel.CodingKeys> = encoder.container(keyedBy: DiceModel.CodingKeys.self)

        try container.encode(self._id, forKey: DiceModel.CodingKeys._id)
        try container.encode(self._name_, forKey: DiceModel.CodingKeys._name_)
        try container.encode(self._description_, forKey: DiceModel.CodingKeys._description_)
        try container.encode(self._tags_, forKey: DiceModel.CodingKeys._tags_)
        try container.encode(self._category_, forKey: DiceModel.CodingKeys._category_)
        try container.encode(self._displayState, forKey: DiceModel.CodingKeys._displayState)
        try container.encode(self._dice_, forKey: DiceModel.CodingKeys._dice_)
        try container.encode(self._sumUp, forKey: DiceModel.CodingKeys._sumUp)
        try container.encode(self._modifier, forKey: DiceModel.CodingKeys._modifier)
        try container.encode(self._percentDice, forKey: DiceModel.CodingKeys._percentDice)
        try container.encode(self._compareOption, forKey: DiceModel.CodingKeys._compareOption)
        try container.encode(self._compareValue, forKey: DiceModel.CodingKeys._compareValue)
        try container.encode(self._coupValues, forKey: DiceModel.CodingKeys._coupValues)
        try container.encode(self._coupOnlyOnFirstDie, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
        try container.encode(self._fumbleValues, forKey: DiceModel.CodingKeys._fumbleValues)
        try container.encode(self._fumbleOnlyOnFirstDie, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
        try container.encode(self._rerollOptions, forKey: DiceModel.CodingKeys._rerollOptions)
        try container.encode(self._reorderDice, forKey: DiceModel.CodingKeys._reorderDice)
        try container.encode(self._addDiceEvery, forKey: DiceModel.CodingKeys._addDiceEvery)
        try container.encodeIfPresent(self._resultCategory, forKey: DiceModel.CodingKeys._resultCategory)
    }
}

extension DiceModel: Equatable, Hashable {
    public static func == (lhs: DiceModel, rhs: DiceModel) -> Bool {
        lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState && lhs.resultCategory == rhs.resultCategory
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
