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
        self._dice_ = Self.bounded(dice: try container.decode(CRDTDataUpdate<[DieModel]>.self, forKey: DiceModel.CodingKeys._dice_))
        self._sumUp = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._sumUp)
        self._modifier = Self.boundedValue(try container.decode(Double.self, forKey: DiceModel.CodingKeys._modifier))
        self._percentDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._percentDice)
        self._compareOption = try container.decode(DiceModel.CompareValue.self, forKey: DiceModel.CodingKeys._compareOption)
        self._compareValue = Self.boundedValue(try container.decode(Double.self, forKey: DiceModel.CodingKeys._compareValue))
        self._coupValues = Self.bounded(options: try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._coupValues))
        self._coupOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._coupOnlyOnFirstDie)
        self._fumbleValues = Self.bounded(options: try container.decode([DiceModel.CoupFumbleOption].self, forKey: DiceModel.CodingKeys._fumbleValues))
        self._fumbleOnlyOnFirstDie = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._fumbleOnlyOnFirstDie)
        self._rerollOptions = Self.bounded(options: try container.decode([DiceModel.RerollOption].self, forKey: DiceModel.CodingKeys._rerollOptions))
        self._reorderDice = try container.decode(Bool.self, forKey: DiceModel.CodingKeys._reorderDice)
        self._addDiceEvery = Self.boundedDiceEvery(try container.decode(Int.self, forKey: DiceModel.CodingKeys._addDiceEvery))
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

    /// Writes rolled state (results, rotation) without moving the dice's update marker. A roll is
    /// not an edit: `merge` arbitrates every plain field by the marker, so a roll made on a library
    /// set after another device's edit but before it synced would otherwise win the merge and undo
    /// that edit. See CODE_AUDIT_26 §5.35.
    @MainActor
    func setRolledDice(_ rolled: [DieModel]) {
        guard dice_.wrappedValue != rolled else { return }
        dice_ = CRDTDataUpdate(wrappedValue: rolled, update: dice_.$update)
    }

    public var sumUp: Bool = true
    public var modifier: Double = 0.0
    public var percentDice: Bool = false


    public var compareOption: CompareValue = .off
    public var compareValue: Double = 0.0 {
        didSet {
            resetDice()
        }
    }


    public var coupValues: [CoupFumbleOption] = []
    public var coupOnlyOnFirstDie: Bool = false

    public var fumbleValues: [CoupFumbleOption] = []
    public var fumbleOnlyOnFirstDie: Bool = false


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
    
    var maxValue: Int {
        dice.reduce(0) { $0.saturatingSum($1.die.max) }
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

// Members are in DiceModel+ItemData.swift.
extension DiceModel: nonisolated ItemDataAccessible {}
