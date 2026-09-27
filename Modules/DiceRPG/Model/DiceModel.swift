// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as DiceSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class DiceModel: nonisolated Identifiable {
    nonisolated public init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, dice: [DieModel], sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil, entries: [ChildEntryModel] = [], parentId: UUID? = nil) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _dice_ = CRDTDataUpdate(wrappedValue: dice)
        self._sumUp = sumUp
        self._modifier = modifier
        self._percentDice = percentDice
        self._compareOption = compareOption
        self._compareValue = compareValue
        self._coupValues = coupValues
        self._coupOnlyOnFirstDie = coupOnlyOnFirstDie
        self._fumbleValues = fumbleValues
        self._fumbleOnlyOnFirstDie = fumbleOnlyOnFirstDie
        self._rerollOptions = rerollOptions
        self._reorderDice = reorderDice
        self._addDiceEvery = addDiceEvery
        self._resultCategory = resultCategory
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        self._parentId = parentId
    }

    nonisolated init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, dice: CRDTDataUpdate<[DieModel]>, sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _dice_ = dice
        self._sumUp = sumUp
        self._modifier = modifier
        self._percentDice = percentDice
        self._compareOption = compareOption
        self._compareValue = compareValue
        self._coupValues = coupValues
        self._coupOnlyOnFirstDie = coupOnlyOnFirstDie
        self._fumbleValues = fumbleValues
        self._fumbleOnlyOnFirstDie = fumbleOnlyOnFirstDie
        self._rerollOptions = rerollOptions
        self._reorderDice = reorderDice
        self._addDiceEvery = addDiceEvery
        self._resultCategory = resultCategory
        _entries_ = entries
        self._parentId = parentId
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<DiceModel.CodingKeys> = try decoder.container(keyedBy: DiceModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: DiceModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: DiceModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: DiceModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: DiceModel.CodingKeys._displayState)
        self._dice_ = try container.decode(CRDTDataUpdate<[DieModel]>.self, forKey: DiceModel.CodingKeys._dice_)
        self._sumUp = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._sumUp)
        self._modifier = Self.boundedValue(try container.decode(Double.self, forKey: DiceModel.CodingKeys._modifier))
        self._percentDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._percentDice)
        self._compareOption = try container.decode(DiceModel.CompareValue.self, forKey: DiceModel.CodingKeys._compareOption)
        self._compareValue = Self.boundedValue(try container.decode(Double.self, forKey: DiceModel.CodingKeys._compareValue))
        self._coupValues = try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._coupValues)
        self._coupOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
        self._fumbleValues = try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._fumbleValues)
        self._fumbleOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
        self._rerollOptions = try container.decode([DiceModel.RerollOption].self, forKey: DiceModel.CodingKeys._rerollOptions)
        self._reorderDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._reorderDice)
        self._addDiceEvery = try container.decode(Int.self, forKey: DiceModel.CodingKeys._addDiceEvery)
        self._resultCategory = try container.decodeIfPresent(ResultCategory.self, forKey: DiceModel.CodingKeys._resultCategory)
        self._entries_ = try container.decodeIfPresent(CRDTDataUpdate<[ChildEntryModel]>.self, forKey: DiceModel.CodingKeys._entries_) ?? CRDTDataUpdate<[ChildEntryModel]>(wrappedValue: [])
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: DiceModel.CodingKeys._parentId)
    }
    
    // `let`: nonisolated access (Identifiable, hashing) per SE-0434.
    public let id: UUID
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

    public var dice: [DieModel] {
        get { dice_.wrappedValue }
        set { dice_.wrappedValue = newValue }
    }
    var dice_: CRDTDataUpdate<[DieModel]>

    public var sumUp: Bool = true
    public var modifier: Double = 0.0
    public var percentDice: Bool = false

    public enum CompareValue: Int, Identifiable, Equatable, Hashable, Codable, CaseIterable, Sendable {
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

    public var compareOption: CompareValue = .off
    public var compareValue: Double = 0.0 {
        didSet {
            resetDice()
        }
    }

    public enum CoupFumbleOption: Identifiable, Equatable, Hashable, Codable, RawRepresentable, Sendable {
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

    public var coupValues: [CoupFumbleOption] = []
    public var coupOnlyOnFirstDie: Bool = false

    public var fumbleValues: [CoupFumbleOption] = []
    public var fumbleOnlyOnFirstDie: Bool = false

    public struct RerollOption: Identifiable, Equatable, Hashable, Codable, Sendable {
        public let number: Int
        public let value: Int
        public let maxDiceValue: Bool

        public var id: Int {
            number
        }
    }

    public var rerollOptions: [RerollOption] = []

    public var reorderDice: Bool = false
    public var addDiceEvery: Int = 0 {
        didSet {
            resetDice()
        }
    }

    var resultCategory: ResultCategory? = nil
    
    public var entries: [ChildEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[ChildEntryModel]>

    public var parentId: UUID? = nil
}

extension DiceModel {
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

    var canPercentDice: Bool {
        guard dice.count == 2 else { return false }
        return dice[0].die.sides == .ten && dice[1].die.sides == .ten
    }
    
    var inlineText: String {
        var diceModel = RawDice(dice: dice.map { $0.die })
        diceModel.modifier = modifier.saturatingInt
        return diceModel.text
    }
    
    /// Largest magnitude accepted for a decoded modifier or compare value; it also fits `Float`
    /// storage. Non-finite values become 0. See CODE_AUDIT_16 §5.4.
    nonisolated static let maximumValueMagnitude = 1_000_000_000.0

    nonisolated static func boundedValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -maximumValueMagnitude), maximumValueMagnitude)
    }

    /// Most dice a compare value can add. See CODE_AUDIT_16 §5.4.
    static let maximumDiceCount = 100

    func resetDice() {
        guard addDiceEvery > 0 else { return }
        let compare = compareValue.saturatingInt
        var number = compare / addDiceEvery + (compare % addDiceEvery > 0 ? 1 : 0)
        // The compare value can come from any calculated Character value; bound the allocation.
        number = min(max(number, 1), Self.maximumDiceCount)
        if dice.count != number, let die = dice.first {
            dice = (1 ... number).map { _ in die.duplicate() }
        }
    }
    
    func applyResult(text: String) {
        let diceResult = text.split(separator: "|")
        guard diceResult.count == dice.count else { return }
        for index in 0 ..< dice.count {
            let dieResult = diceResult[index]
                .split(separator: ",", omittingEmptySubsequences: false)
                .compactMap { Int($0) }
            let die = dice[index].applyResult(values: dieResult)
            dice[index] = die
        }
    }
    
    var minValue: Int {
        dice.reduce(0) { $0 + $1.die.min }
    }
    
    var maxValue: Int {
        dice.reduce(0) { $0 + $1.die.max }
    }
    
    var minFirstValue: Int {
        dice.first?.die.min ?? 1
    }

    var maxFirstValue: Int {
        dice.first?.die.max ?? 20
    }
}

extension DiceModel: nonisolated Comparable {
    nonisolated public static func < (lhs: DiceModel, rhs: DiceModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension DiceModel: nonisolated ItemLinkRegistrable {}

extension DiceModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: DiceModel) -> DiceModel {
        return assumeMainActorIsolated {
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
                // Was always `resultCategory` (self), silently discarding the
                // peer's incoming change on every merge conflict — the only
                // scalar field in this initializer that wasn't arbitrated
                // like its siblings. See CODE_AUDIT_13 §5.3.
                resultCategory: isLeftDice ? resultCategory : other.resultCategory,
                entries: entries_.merged(other: other.entries_),
                parentId: other.parentId
            )
    
        }
    }

    nonisolated public func isSame(_ other: DiceModel) -> Bool {
        return assumeMainActorIsolated {
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
}

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

extension DiceModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> DiceModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            let dupDice = dice.map { dieVM -> DieModel in
                DieModel(id: UUID(), die: dieVM.die)
            }
            return DiceModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, dice: dupDice, sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, rerollOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery, entries: entries.map { $0.duplicate() }, parentId: parentId)
    
        }
    }
}

extension DiceModel: nonisolated ItemDataAccessible {
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
            try container.encode(self._entries_, forKey: DiceModel.CodingKeys._entries_)
            try container.encodeIfPresent(self._parentId, forKey: DiceModel.CodingKeys._parentId)
    
        }
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
