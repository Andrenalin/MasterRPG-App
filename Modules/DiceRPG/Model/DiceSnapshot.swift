// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a DiceModel — the representation that crosses
/// isolation and process boundaries: Core Data context, game network payloads
/// (DiceResultModel), widget configuration and Live Activity content state.
///
/// Codable is byte-identical to DiceModel's Codable (same keys, same optionality),
/// so stored configurations and the game wire format stay compatible.
public struct DiceSnapshot: Sendable, Identifiable {
    public let id: UUID
    let name_: CRDT<String>
    let description_: CRDT<String>
    let tags_: CRDT<[String]>
    let category_: CRDT<ItemListCategory>
    let displayState: Int
    let dice_: CRDTDataUpdate<[DieModel]>
    let sumUp: Bool
    let modifier: Double
    let percentDice: Bool
    let compareOption: DiceModel.CompareValue
    let compareValue: Double
    let coupValues: [DiceModel.CoupFumbleOption]
    let coupOnlyOnFirstDie: Bool
    let fumbleValues: [DiceModel.CoupFumbleOption]
    let fumbleOnlyOnFirstDie: Bool
    let rerollOptions: [DiceModel.RerollOption]
    let reorderDice: Bool
    let addDiceEvery: Int
    /// Identifies the sheet item that originated a roll. Game features use
    /// this value to associate a character-linked die with its participant.
    public let resultCategory: ResultCategory?
    let entries_: CRDTDataUpdate<[ChildEntryModel]>
    let parentId: UUID?

    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, dice: CRDTDataUpdate<[DieModel]>, sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil, entries: CRDTDataUpdate<[ChildEntryModel]>, parentId: UUID?) {
        self.id = id
        self.name_ = name
        self.description_ = description
        self.tags_ = tags
        self.category_ = category
        self.displayState = displayState
        self.dice_ = dice
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
        self.entries_ = entries
        self.parentId = parentId
    }

    /// Plain-value convenience mirroring DiceModel's designated init — used by the
    /// widget and previews to build snapshots without touching the MainActor.
    public init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, dice: [DieModel], sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil, entries: [ChildEntryModel] = [], parentId: UUID? = nil) {
        self.init(id: id, name: CRDT(wrappedValue: name), description: CRDT(wrappedValue: description), tags: CRDT(wrappedValue: tags), category: CRDT(wrappedValue: category), displayState: displayState, dice: CRDTDataUpdate(wrappedValue: dice), sumUp: sumUp, modifier: modifier, percentDice: percentDice, compareOption: compareOption, compareValue: compareValue, coupValues: coupValues, coupOnlyOnFirstDie: coupOnlyOnFirstDie, fumbleValues: fumbleValues, fumbleOnlyOnFirstDie: fumbleOnlyOnFirstDie, rerollOptions: rerollOptions, reorderDice: reorderDice, addDiceEvery: addDiceEvery, resultCategory: resultCategory, entries: CRDTDataUpdate(wrappedValue: entries), parentId: parentId)
    }
}

// MARK: - Value accessors (mirror the model API used by widgets and views)

public extension DiceSnapshot {
    var name: String { name_.wrappedValue }
    var description: String { description_.wrappedValue }
    var tags: [String] { tags_.wrappedValue }
    var category: ItemListCategory { category_.wrappedValue }
    var dice: [DieModel] { dice_.wrappedValue }
    var entries: [ChildEntryModel] { entries_.wrappedValue }
}

// MARK: - Model conversion

public extension DiceSnapshot {
    @MainActor
    init(_ model: DiceModel) {
        self.init(
            id: model.id,
            name: model.name_,
            description: model.description_,
            tags: model.tags_,
            category: model.category_,
            displayState: model.displayState,
            dice: model.dice_,
            sumUp: model.sumUp,
            modifier: model.modifier,
            percentDice: model.percentDice,
            compareOption: model.compareOption,
            compareValue: model.compareValue,
            coupValues: model.coupValues,
            coupOnlyOnFirstDie: model.coupOnlyOnFirstDie,
            fumbleValues: model.fumbleValues,
            fumbleOnlyOnFirstDie: model.fumbleOnlyOnFirstDie,
            rerollOptions: model.rerollOptions,
            reorderDice: model.reorderDice,
            addDiceEvery: model.addDiceEvery,
            resultCategory: model.resultCategory,
            entries: model.entries_,
            parentId: model.parentId
        )
    }

    /// Nonisolated on purpose: DiceModel's initializers only initialize stored state.
    func makeModel() -> DiceModel {
        makeModel(withId: id)
    }

    func makeModel(withId newId: UUID) -> DiceModel {
        DiceModel(
            id: newId,
            name: name_,
            description: description_,
            tags: tags_,
            category: category_,
            displayState: displayState,
            dice: dice_,
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
            resultCategory: resultCategory,
            entries: entries_,
            parentId: parentId
        )
    }
}

// MARK: - Codable (byte-identical to DiceModel's wire format)

extension DiceSnapshot: Codable {
    // Same key strings as DiceModel.CodingKeys — do not change.
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: ._id),
            name: try container.decode(CRDT<String>.self, forKey: ._name_),
            description: try container.decode(CRDT<String>.self, forKey: ._description_),
            tags: try container.decode(CRDT<[String]>.self, forKey: ._tags_),
            category: try container.decode(CRDT<ItemListCategory>.self, forKey: ._category_),
            displayState: try container.decode(Int.self, forKey: ._displayState),
            dice: DiceModel.bounded(dice: try container.decode(CRDTDataUpdate<[DieModel]>.self, forKey: ._dice_)),
            sumUp: try container.decode(Bool.self, forKey: ._sumUp),
            modifier: DiceModel.boundedValue(try container.decode(Double.self, forKey: ._modifier)),
            percentDice: try container.decode(Bool.self, forKey: ._percentDice),
            compareOption: try container.decode(DiceModel.CompareValue.self, forKey: ._compareOption),
            compareValue: DiceModel.boundedValue(try container.decode(Double.self, forKey: ._compareValue)),
            coupValues: DiceModel.bounded(options: try container.decode([DiceModel.CoupFumbleOption].self, forKey: ._coupValues)),
            coupOnlyOnFirstDie: try container.decode(Bool.self, forKey: ._coupOnlyOnFirstDie),
            fumbleValues: DiceModel.bounded(options: try container.decode([DiceModel.CoupFumbleOption].self, forKey: ._fumbleValues)),
            fumbleOnlyOnFirstDie: try container.decode(Bool.self, forKey: ._fumbleOnlyOnFirstDie),
            rerollOptions: DiceModel.bounded(options: try container.decode([DiceModel.RerollOption].self, forKey: ._rerollOptions)),
            reorderDice: try container.decode(Bool.self, forKey: ._reorderDice),
            addDiceEvery: DiceModel.boundedDiceEvery(try container.decode(Int.self, forKey: ._addDiceEvery)),
            resultCategory: try container.decodeIfPresent(ResultCategory.self, forKey: ._resultCategory),
            entries: try container.decodeIfPresent(CRDTDataUpdate<[ChildEntryModel]>.self, forKey: ._entries_) ?? CRDTDataUpdate(wrappedValue: []),
            parentId: try container.decodeIfPresent(UUID.self, forKey: ._parentId)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: ._id)
        try container.encode(name_, forKey: ._name_)
        try container.encode(description_, forKey: ._description_)
        try container.encode(tags_, forKey: ._tags_)
        try container.encode(category_, forKey: ._category_)
        try container.encode(displayState, forKey: ._displayState)
        try container.encode(dice_, forKey: ._dice_)
        try container.encode(sumUp, forKey: ._sumUp)
        try container.encode(modifier, forKey: ._modifier)
        try container.encode(percentDice, forKey: ._percentDice)
        try container.encode(compareOption, forKey: ._compareOption)
        try container.encode(compareValue, forKey: ._compareValue)
        try container.encode(coupValues, forKey: ._coupValues)
        try container.encode(coupOnlyOnFirstDie, forKey: ._coupOnlyOnFirstDie)
        try container.encode(fumbleValues, forKey: ._fumbleValues)
        try container.encode(fumbleOnlyOnFirstDie, forKey: ._fumbleOnlyOnFirstDie)
        try container.encode(rerollOptions, forKey: ._rerollOptions)
        try container.encode(reorderDice, forKey: ._reorderDice)
        try container.encode(addDiceEvery, forKey: ._addDiceEvery)
        try container.encodeIfPresent(resultCategory, forKey: ._resultCategory)
        try container.encode(entries_, forKey: ._entries_)
        try container.encodeIfPresent(parentId, forKey: ._parentId)
    }
}

// MARK: - Equatable / Hashable (pure value comparison — no actor hop, no traps)

extension DiceSnapshot: Equatable, Hashable {
    public static func == (lhs: DiceSnapshot, rhs: DiceSnapshot) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.description == rhs.description &&
        lhs.tags == rhs.tags &&
        lhs.category == rhs.category &&
        lhs.displayState == rhs.displayState &&
        lhs.dice_.update == rhs.dice_.update &&
        lhs.sumUp == rhs.sumUp &&
        lhs.modifier == rhs.modifier &&
        lhs.percentDice == rhs.percentDice &&
        lhs.compareOption == rhs.compareOption &&
        lhs.compareValue == rhs.compareValue &&
        lhs.coupValues == rhs.coupValues &&
        lhs.coupOnlyOnFirstDie == rhs.coupOnlyOnFirstDie &&
        lhs.fumbleValues == rhs.fumbleValues &&
        lhs.fumbleOnlyOnFirstDie == rhs.fumbleOnlyOnFirstDie &&
        lhs.rerollOptions == rhs.rerollOptions &&
        lhs.reorderDice == rhs.reorderDice &&
        lhs.addDiceEvery == rhs.addDiceEvery &&
        lhs.resultCategory == rhs.resultCategory &&
        lhs.entries_.update == rhs.entries_.update &&
        lhs.parentId == rhs.parentId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
