// @copyright André Trettin

import Foundation
import Testing
@testable import CoreRPG

private final class MemoryQuickDiceSlotStore: QuickDiceSlotStoring, @unchecked Sendable {
    private(set) var saved: [UUID: [QuickDiceSlot?]] = [:]

    func slots(for characterId: UUID) -> [QuickDiceSlot?] {
        saved[characterId] ?? []
    }

    func save(_ slots: [QuickDiceSlot?], for characterId: UUID) {
        saved[characterId] = slots
    }
}

@MainActor
@Suite("Quick dice slots")
struct QuickDiceSlotsModelTests {
    private let characterId = UUID()
    private let itemId = UUID()
    private let entryId = UUID()

    @Test("A new model has four empty slots")
    func startsEmpty() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())

        #expect(sut.slots.count == QuickDiceSlotsModel.slotCount)
        #expect(sut.slots.allSatisfy { $0 == nil })
    }

    @Test("Slots are saved per character and restored on load")
    func savedPerCharacter() {
        let store = MemoryQuickDiceSlotStore()
        let first = QuickDiceSlotsModel(store: store)
        let diceId = UUID()
        first.load(characterId: characterId)
        first.assign(QuickDiceSlot(source: .dice(diceId: diceId), manualValue: 12), to: 2)

        let second = QuickDiceSlotsModel(store: store)
        second.load(characterId: characterId)
        #expect(second.slots[2]?.source == .dice(diceId: diceId))
        #expect(second.slots[2]?.manualValue == 12)

        second.load(characterId: UUID())
        #expect(second.slots.allSatisfy { $0 == nil })
    }

    @Test("Without a character nothing is saved")
    func noCharacterNoSave() {
        let store = MemoryQuickDiceSlotStore()
        let sut = QuickDiceSlotsModel(store: store)

        sut.assign(QuickDiceSlot(source: .dice(diceId: UUID())), to: 0)

        #expect(store.saved.isEmpty)
    }

    @Test("An entry lives in one slot, moving when assigned again")
    func entryMoves() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        sut.load(characterId: characterId)
        let slot = QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId))

        sut.assign(slot, to: 0)
        sut.assign(slot, to: 3)

        #expect(sut.slots[0] == nil)
        #expect(sut.index(forItem: itemId, entry: entryId) == 3)
    }

    @Test("The same base dice may fill several slots")
    func diceRepeats() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        sut.load(characterId: characterId)
        let slot = QuickDiceSlot(source: .dice(diceId: UUID()))

        sut.assign(slot, to: 0)
        sut.assign(slot, to: 1)

        #expect(sut.slots[0] == slot)
        #expect(sut.slots[1] == slot)
    }

    @Test("Clearing and out-of-range indices")
    func clearAndBounds() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        sut.load(characterId: characterId)
        sut.assign(QuickDiceSlot(source: .dice(diceId: UUID())), to: 1)

        sut.assign(QuickDiceSlot(source: .dice(diceId: UUID())), to: 9)
        sut.clear(9)
        sut.clear(1)

        #expect(sut.slots.allSatisfy { $0 == nil })
    }

    @Test("The base dice's game copy is remembered only for the dice that made it")
    func gameDiceMemory() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        let diceId = UUID()
        let gameDiceId = UUID()

        sut.rememberGameDiceId(gameDiceId, at: 0, for: diceId)

        #expect(sut.gameDiceId(at: 0, for: diceId) == gameDiceId)
        #expect(sut.gameDiceId(at: 0, for: UUID()) == nil)

        sut.assign(QuickDiceSlot(source: .dice(diceId: diceId)), to: 0)
        #expect(sut.gameDiceId(at: 0, for: diceId) == nil)
    }

    @Test("Assigning the same dice again keeps its game copy, another dice drops it")
    func sameDiceKeepsGameCopy() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        let diceId = UUID()
        let gameDiceId = UUID()
        sut.assign(QuickDiceSlot(source: .dice(diceId: diceId)), to: 0)
        sut.rememberGameDiceId(gameDiceId, at: 0, for: diceId)

        sut.assign(QuickDiceSlot(source: .dice(diceId: diceId), manualValue: 5), to: 0)
        #expect(sut.gameDiceId(at: 0, for: diceId) == gameDiceId)

        sut.assign(QuickDiceSlot(source: .dice(diceId: UUID())), to: 0)
        #expect(sut.gameDiceId(at: 0, for: diceId) == nil)
    }

    @Test("A manual value is bounded when assigned, set and loaded")
    func manualValueIsBounded() {
        let store = MemoryQuickDiceSlotStore()
        let sut = QuickDiceSlotsModel(store: store)
        sut.load(characterId: characterId)
        let diceId = UUID()

        sut.assign(QuickDiceSlot(source: .dice(diceId: diceId), manualValue: .max), to: 0)
        #expect(sut.slots[0]?.manualValue == QuickDiceSlot.maximumValue)

        sut.setManualValue(1, at: 0)
        sut.setManualValue(.max, at: 0)
        #expect(sut.slots[0]?.manualValue == QuickDiceSlot.maximumValue)
        // Values of 0 or less are ignored since CODE_AUDIT_Since_3.0.1 §5.12.
        sut.setManualValue(.min, at: 0)
        #expect(sut.slots[0]?.manualValue == QuickDiceSlot.maximumValue)

        store.save([QuickDiceSlot(source: .dice(diceId: diceId), manualValue: .max), nil, nil, nil], for: characterId)
        let reloaded = QuickDiceSlotsModel(store: store)
        reloaded.load(characterId: characterId)
        #expect(reloaded.slots[0]?.manualValue == QuickDiceSlot.maximumValue)
    }

    @Test("An override wins over the linked value until the linked value changes")
    func overrideLasts() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        sut.assign(QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId)), to: 1)

        #expect(sut.effectiveValue(linkedValue: 5, at: 1) == 5)

        #expect(sut.setOverride(8, linkedValue: 5, at: 1))
        #expect(sut.effectiveValue(linkedValue: 5, at: 1) == 8)
        #expect(sut.effectiveValue(linkedValue: 5, forItem: itemId, entry: entryId) == 8)

        // The entry's value moved on: its own value is back, and the override stays gone
        // even when the value later returns to the one it was made against.
        #expect(sut.effectiveValue(linkedValue: 6, at: 1) == 6)
        sut.linkedValueChanged(6, at: 1)
        #expect(sut.effectiveValue(linkedValue: 5, at: 1) == 5)
    }

    @Test("An override is ignored when it is not positive, and ends with the slot's dice")
    func overrideRules() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        let slot = QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId))
        sut.assign(slot, to: 0)

        #expect(!sut.setOverride(0, linkedValue: 5, at: 0))
        #expect(!sut.setOverride(-3, linkedValue: 5, at: 0))
        #expect(!sut.setOverride(4, linkedValue: 5, at: 7))
        #expect(sut.effectiveValue(linkedValue: 5, at: 0) == 5)

        sut.setOverride(4, linkedValue: 5, at: 0)
        sut.assign(slot, to: 0)
        #expect(sut.effectiveValue(linkedValue: 5, at: 0) == 5)

        sut.setOverride(4, linkedValue: 5, at: 0)
        sut.clear(0)
        #expect(sut.effectiveValue(linkedValue: 5, at: 0) == 5)
    }

    /// CODE_AUDIT_Since_3.0.1 §5.13: with the overlay hidden nothing called `linkedValueChanged`,
    /// so an A→B→A change brought the stale override back.
    @Test("An override ends in the model, also when only the sheet row reads it")
    func overrideEndsWithoutTheOverlay() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())
        sut.assign(QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId)), to: 1)
        sut.setOverride(8, linkedValue: 5, at: 1)

        #expect(sut.effectiveValue(linkedValue: 6, forItem: itemId, entry: entryId) == 6)
        #expect(sut.effectiveValue(linkedValue: 5, forItem: itemId, entry: entryId) == 5)
        #expect(sut.effectiveValue(linkedValue: 5, at: 1) == 5)

        // A new override is good again.
        #expect(sut.setOverride(9, linkedValue: 5, at: 1))
        #expect(sut.effectiveValue(linkedValue: 5, at: 1) == 9)
    }

    /// CODE_AUDIT_Since_3.0.1 §5.12: a manual value of 0 was saved, and the dice ignored it.
    @Test("A base dice slot keeps no manual value of 0 or less")
    func manualValueMustBePositive() {
        let store = MemoryQuickDiceSlotStore()
        let sut = QuickDiceSlotsModel(store: store)
        sut.load(characterId: characterId)
        sut.assign(QuickDiceSlot(source: .dice(diceId: UUID()), manualValue: 12), to: 0)

        #expect(!sut.setManualValue(0, at: 0))
        #expect(!sut.setManualValue(-4, at: 0))
        #expect(sut.slots[0]?.manualValue == 12)
        #expect(sut.setManualValue(15, at: 0))
        #expect(store.slots(for: characterId)[0]?.manualValue == 15)
        #expect(sut.setManualValue(nil, at: 0))
        #expect(sut.slots[0]?.manualValue == nil)
    }

    @Test("A sheet row of an entry without a slot just uses the linked value")
    func rowWithoutSlot() {
        let sut = QuickDiceSlotsModel(store: MemoryQuickDiceSlotStore())

        #expect(sut.effectiveValue(linkedValue: 7, forItem: itemId, entry: entryId) == 7)
        #expect(sut.effectiveValue(linkedValue: nil, forItem: itemId, entry: entryId) == nil)
    }

    @Test("The UserDefaults store round-trips and forgets emptied characters")
    func userDefaultsStore() throws {
        let suiteName = "QuickDiceSlotsModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsQuickDiceSlotStore(defaults: defaults)
        let slot = QuickDiceSlot(source: .entry(itemId: itemId, entryId: entryId))

        store.save([slot, nil, nil, nil], for: characterId)
        #expect(store.slots(for: characterId) == [slot, nil, nil, nil])

        store.save([nil, nil, nil, nil], for: characterId)
        #expect(store.slots(for: characterId).isEmpty)
    }
}
