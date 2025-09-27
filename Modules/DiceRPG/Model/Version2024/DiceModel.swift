// @copyright André Trettin

import CoreRPG
import Foundation

struct DiceModel: Identifiable, Sendable, Codable, Equatable, Hashable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int = 0, dice: CRDTDataUpdate<[DieModel]>, sumUp: Bool = true, modifier: Double = 0.0, percentDice: Bool = false, compareOption: DiceDataModel.CompareValue = .off, compareValue: Double = 0.0, coupValues: [DiceDataModel.CoupFumbleOption] = [], coupOnlyOnFirstDie: Bool = false, fumbleValues: [DiceDataModel.CoupFumbleOption] = [], fumbleOnlyOnFirstDie: Bool = false, rerollOptions: [DiceDataModel.RerollOption] = [], reorderDice: Bool = false, addDiceEvery: Int = 0, resultCategory: ResultCategory? = nil) {
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

    var id: UUID
    var name_: CRDT<String>
    var description_: CRDT<String>
    var tags_: CRDT<[String]>
    var category_: CRDT<ItemListCategory>
    var displayState: Int
    var dice_: CRDTDataUpdate<[DieModel]>

    var sumUp: Bool = true
    var modifier: Double = 0.0
    var percentDice: Bool = false

    var compareOption: DiceDataModel.CompareValue = .off
    var compareValue: Double = 0.0

    var coupValues: [DiceDataModel.CoupFumbleOption] = []
    var coupOnlyOnFirstDie: Bool = false

    var fumbleValues: [DiceDataModel.CoupFumbleOption] = []
    var fumbleOnlyOnFirstDie: Bool = false

    var rerollOptions: [DiceDataModel.RerollOption] = []

    var reorderDice: Bool = false
    var addDiceEvery: Int = 0

    var resultCategory: ResultCategory? = nil

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

    func encode(to encoder: Encoder) throws {
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
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<DiceModel.CodingKeys> = try decoder.container(keyedBy: DiceModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: DiceModel.CodingKeys._id)
        self.name_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._name_)
        self.description_ = try container.decode(CRDT<String>.self, forKey: DiceModel.CodingKeys._description_)
        self.tags_ = try container.decode(CRDT<[String]>.self, forKey: DiceModel.CodingKeys._tags_)
        self.category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: DiceModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: DiceModel.CodingKeys._displayState)
        self.dice_ = try container.decode(CRDTDataUpdate<[DieModel]>.self, forKey: DiceModel.CodingKeys._dice_)
        self.sumUp = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._sumUp)
        self.modifier = try container.decode(Double.self, forKey: DiceModel.CodingKeys._modifier)
        self.percentDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._percentDice)
        self.compareOption = try container.decode(DiceDataModel.CompareValue.self, forKey: DiceModel.CodingKeys._compareOption)
        self.compareValue = try container.decode(Double.self, forKey: DiceModel.CodingKeys._compareValue)
        self.coupValues = try container.decode([DiceDataModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._coupValues)
        self.coupOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
        self.fumbleValues = try container.decode([DiceDataModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._fumbleValues)
        self.fumbleOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
        self.rerollOptions = try container.decode([DiceDataModel.RerollOption].self, forKey: DiceModel.CodingKeys._rerollOptions)
        self.reorderDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._reorderDice)
        self.addDiceEvery = try container.decode(Int.self, forKey: DiceModel.CodingKeys._addDiceEvery)
        self.resultCategory = try container.decodeIfPresent(ResultCategory.self, forKey: DiceModel.CodingKeys._resultCategory)
    }
}
