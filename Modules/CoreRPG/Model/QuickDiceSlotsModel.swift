// @copyright André Trettin

import Foundation
import Observation
import SwiftUI

/// One of the quick dice overlay's slots: a character entry's dice that follows the entry's
/// value, or a base dice picked from the dice list.
public struct QuickDiceSlot: Codable, Hashable, Sendable {
    public enum Source: Codable, Hashable, Sendable {
        /// `itemId` is the item that directly contains the entry (a group's item for a nested entry).
        case entry(itemId: UUID, entryId: UUID)
        case dice(diceId: UUID)
    }

    public var source: Source
    /// The compare value of a `.dice` slot. An `.entry` slot takes its value from the entry,
    /// and a temporary override of it is view state that is never persisted.
    public var manualValue: Int?

    public init(source: Source, manualValue: Int? = nil) {
        self.source = source
        self.manualValue = manualValue
    }

    /// Largest compare value a slot keeps, the same bound a dice model accepts when decoding.
    public static let maximumValue = 1_000_000_000
}

/// A value typed over a sheet-linked slot, good for as long as the entry's value is the one it
/// was typed against.
public struct QuickDiceOverride: Equatable, Sendable {
    public let value: Int
    public let linkedValue: Int?
}

public protocol QuickDiceSlotStoring: Sendable {
    func slots(for characterId: UUID) -> [QuickDiceSlot?]
    func save(_ slots: [QuickDiceSlot?], for characterId: UUID)
}

/// Keeps each character's slots in `UserDefaults`, like the other game settings.
public struct UserDefaultsQuickDiceSlotStore: QuickDiceSlotStoring {
    // `UserDefaults` is thread-safe by documentation but not yet `Sendable` in this SDK.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func slots(for characterId: UUID) -> [QuickDiceSlot?] {
        guard let data = defaults.data(forKey: Self.key(for: characterId)),
              let slots = try? JSONDecoder().decode([QuickDiceSlot?].self, from: data) else { return [] }
        return slots
    }

    public func save(_ slots: [QuickDiceSlot?], for characterId: UUID) {
        let key = Self.key(for: characterId)
        guard slots.contains(where: { $0 != nil }) else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: key)
    }

    private static func key(for characterId: UUID) -> String {
        "quickDiceSlots.\(characterId.uuidString)"
    }
}

/// The four quick dice slots of the game character the player is playing.
@MainActor @Observable
public final class QuickDiceSlotsModel {
    public static let slotCount = 4

    public init(store: any QuickDiceSlotStoring = UserDefaultsQuickDiceSlotStore()) {
        self.store = store
    }

    public private(set) var slots: [QuickDiceSlot?] = Array(repeating: nil, count: QuickDiceSlotsModel.slotCount)
    public private(set) var characterId: UUID?

    /// The temporary overrides of `.entry` slots by slot index. Session-only.
    public private(set) var overrides: [Int: QuickDiceOverride] = [:]

    /// Slots whose override saw its entry's value change. Such an override never comes back, even
    /// when the value returns to the one it was made against. Kept out of observation because
    /// `effectiveValue` marks it while a view's body reads it. See CODE_AUDIT_Since_3.0.1 §5.13.
    @ObservationIgnored private var outdatedOverrides: Set<Int> = []

    @ObservationIgnored private let store: any QuickDiceSlotStoring
    /// The game copy of each `.dice` slot's base dice, so the same copy keeps its results for
    /// as long as the slot holds that dice. Session-only.
    @ObservationIgnored private var gameDice: [Int: (diceId: UUID, gameDiceId: UUID)] = [:]

    /// Switches to `characterId`'s saved slots, or empty slots without a character.
    public func load(characterId: UUID?) {
        guard self.characterId != characterId else { return }
        self.characterId = characterId
        var loaded = characterId.map { store.slots(for: $0) } ?? []
        loaded = Array(loaded.prefix(Self.slotCount))
        loaded += Array(repeating: nil, count: Self.slotCount - loaded.count)
        slots = loaded.map { slot in
            guard var slot else { return nil }
            slot.manualValue = slot.manualValue.map(Self.boundedValue)
            return slot
        }
        gameDice = [:]
        overrides = [:]
        outdatedOverrides = []
    }

    /// The game copy made for the base dice `diceId` in slot `index`, if there is one.
    public func gameDiceId(at index: Int, for diceId: UUID) -> UUID? {
        guard let entry = gameDice[index], entry.diceId == diceId else { return nil }
        return entry.gameDiceId
    }

    public func rememberGameDiceId(_ gameDiceId: UUID, at index: Int, for diceId: UUID) {
        gameDice[index] = (diceId, gameDiceId)
    }

    /// Puts `slot` at `index`. An entry lives in one slot at a time, so it leaves the one it held.
    public func assign(_ slot: QuickDiceSlot, to index: Int) {
        guard slots.indices.contains(index) else { return }
        if case .entry = slot.source {
            for other in slots.indices where other != index && slots[other]?.source == slot.source {
                slots[other] = nil
                gameDice[other] = nil
                overrides[other] = nil
                outdatedOverrides.remove(other)
            }
        }
        var slot = slot
        slot.manualValue = slot.manualValue.map(Self.boundedValue)
        // The same dice again keeps its game copy, and with it the results of its rolls.
        if slots[index]?.source != slot.source {
            gameDice[index] = nil
        }
        slots[index] = slot
        overrides[index] = nil
        outdatedOverrides.remove(index)
        persist()
    }

    public func clear(_ index: Int) {
        guard slots.indices.contains(index), slots[index] != nil else { return }
        slots[index] = nil
        gameDice[index] = nil
        overrides[index] = nil
        outdatedOverrides.remove(index)
        persist()
    }

    /// Sets the compare value of the base-dice slot at `index`. A value the dice would not take
    /// (0 or less) is ignored, as `setOverride` does. See CODE_AUDIT_Since_3.0.1 §5.12.
    @discardableResult
    public func setManualValue(_ value: Int?, at index: Int) -> Bool {
        if let value, value <= 0 { return false }
        let value = value.map(Self.boundedValue)
        guard slots.indices.contains(index), slots[index]?.manualValue != value else { return false }
        slots[index]?.manualValue = value
        persist()
        return true
    }

    /// The slot that holds this entry, for the favorite menu's checkmark.
    public func index(forItem itemId: UUID, entry entryId: UUID) -> Int? {
        slots.firstIndex { $0?.source == .entry(itemId: itemId, entryId: entryId) }
    }

    // MARK: Overrides

    /// Overrides the value of the entry slot at `index` until `linkedValue`, the entry's own
    /// value, changes. A value the dice would not take (0 or less) is ignored.
    @discardableResult
    public func setOverride(_ value: Int, linkedValue: Int?, at index: Int) -> Bool {
        guard slots.indices.contains(index), value > 0 else { return false }
        overrides[index] = QuickDiceOverride(value: Self.boundedValue(value), linkedValue: linkedValue)
        outdatedOverrides.remove(index)
        return true
    }

    /// The value the dice of the entry slot at `index` use: the override while the entry's value
    /// is still the one it was made against, the entry's value otherwise. Seeing another value
    /// ends the override here, in the model, so it also ends while only the sheet's row reads it
    /// (the overlay hidden). See CODE_AUDIT_Since_3.0.1 §5.13.
    public func effectiveValue(linkedValue: Int?, at index: Int) -> Int? {
        guard let override = overrides[index], !outdatedOverrides.contains(index) else { return linkedValue }
        guard override.linkedValue == linkedValue else {
            outdatedOverrides.insert(index)
            return linkedValue
        }
        return override.value
    }

    /// `effectiveValue(linkedValue:at:)` for the slot that holds this entry, for the sheet's own
    /// dice row, which shares the dice with the slot.
    public func effectiveValue(linkedValue: Int?, forItem itemId: UUID, entry entryId: UUID) -> Int? {
        guard let index = index(forItem: itemId, entry: entryId) else { return linkedValue }
        return effectiveValue(linkedValue: linkedValue, at: index)
    }

    /// Drops the override at `index` once the entry's value is no longer the one it was made
    /// against, so it cannot come back when the value returns to it later.
    public func linkedValueChanged(_ linkedValue: Int?, at index: Int) {
        guard let override = overrides[index], override.linkedValue != linkedValue else { return }
        overrides[index] = nil
        outdatedOverrides.remove(index)
    }

    public static func boundedValue(_ value: Int) -> Int {
        min(max(value, -QuickDiceSlot.maximumValue), QuickDiceSlot.maximumValue)
    }

    private func persist() {
        guard let characterId else { return }
        store.save(slots, for: characterId)
    }
}

public extension EnvironmentValues {
    /// `nil` outside a player's game, so views shared with the editor can offer nothing.
    @Entry var quickDiceSlots: QuickDiceSlotsModel? = nil
}
