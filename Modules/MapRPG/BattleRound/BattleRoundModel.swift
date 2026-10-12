// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

// Plain value types (BattleInitiativeOrder, BattleValueKind, BattleRollResult,
// BattleCombatant, BattleRoundEntry, BattleRoundNetworkState) live in
// BattleRoundTypes.swift.
//
// The class is split by concern across extension files:
// - BattleRoundModel+Roster.swift: roster mutation, character assignment, reset
// - BattleRoundModel+Turns.swift: battle lifecycle, initiative/value config, turn progression, synchronize
// - BattleRoundModel+Rolls.swift: rolls
// - BattleRoundModel+Network.swift: network sync
//
// `sortEntries`/`repositionEntry(for:)`/`retentionKey(for:)`/
// `bumpNetworkSequence`/`retainedPlayer*` below are internal rather than
// `private` so those files can reach them — Swift's `private` only extends
// to same-file extensions.

@MainActor @Observable
public final class BattleRoundModel: Sendable {
    public init() {}

    // MARK: - State

    // `internal(set)` rather than `private(set)`: mutated from
    // BattleRoundModel+Roster.swift/+Turns.swift/+Network.swift, since this
    // class is split across files.
    public internal(set) var isRunning = false
    public internal(set) var mapId: UUID?
    public internal(set) var roundCounter = 0
    /// The order the turn list is sorted by. `BattleRoundSettingsModel` owns
    /// the game master's choice; `GameController` copies it here when it
    /// changes and when a battle begins, so it is not settable from outside
    /// the module.
    public internal(set) var initiativeOrder: BattleInitiativeOrder = .descending
    /// `combatant(id:)`/`combatant(pinId:)` are called from the live render
    /// path (one per pin, every canvas redraw during a battle — see
    /// `MapPinContentView` in `MapPinView.swift`), so a linear scan here
    /// becomes effectively O(n²) per redraw. `didSet` keeps the index
    /// dictionaries below in sync with every mutation, including in-place
    /// element writes like `combatants[index].pin = pin`.
    public internal(set) var combatants: [BattleCombatant] = [] {
        didSet { rebuildCombatantIndex() }
    }
    public internal(set) var entries: [BattleRoundEntry] = []
    public internal(set) var activeAttackerId: UUID?
    public internal(set) var rollRecipientCombatantId: UUID?
    public internal(set) var networkSequence = 0
    public internal(set) var presentedActivePinId: UUID?

    /// Player initiative is retained when a battle closes. Room combatants are
    /// rebuilt for every new battle so the next activated room supplies a fresh
    /// group of monster instances.
    var retainedPlayerInitiatives: [UUID: Int] = [:]
    var retainedPlayerCombatants: [UUID: BattleCombatant] = [:]

    /// Backing store for `cardPresentations` (see `BattleRoundCardPresentation.swift`).
    /// A stored property can only live on the type's own declaration, not on
    /// the extension that defines the computed property itself, which is why
    /// it's declared here rather than alongside `cardPresentations`.
    ///
    /// Not observed: the getter fills it while a view body runs, and an
    /// observed write there would invalidate every reader a second time. Its
    /// inputs (`combatants`, `entries`, …) are observed, which is what a view
    /// has to depend on.
    @ObservationIgnored
    var cardPresentationsCache: (key: CardPresentationsCacheKey, value: [BattleRoundCardPresentation])?

    // Derived from `combatants` in its `didSet`; readers depend on
    // `combatants` itself, so the indexes stay out of observation.
    @ObservationIgnored private var combatantIndexById: [UUID: Int] = [:]
    @ObservationIgnored private var combatantIndexByPinId: [UUID: Int] = [:]

    // MARK: - Combatant lookups

    public var activeEntry: BattleRoundEntry? {
        guard let activeAttackerId else { return nil }
        return entries.first { $0.attackerId == activeAttackerId }
    }

    public var activePinId: UUID? {
        guard let activeAttackerId else { return presentedActivePinId }
        return combatant(id: activeAttackerId)?.pinId ?? presentedActivePinId
    }

    /// The surprise round remains open for adding combatants until the master
    /// explicitly activates an attacker or advances to the first round.
    public var isPreparingSurprise: Bool {
        isRunning && roundCounter == 0 && activeAttackerId == nil
    }

    /// Combatants whose photos can receive a roll in the current battle UI.
    /// During Surprise every combatant receives rolls on its own row. Once a
    /// turn is active, rolls are limited to that attacker and its defenders.
    public var rollEligibleCombatants: [BattleCombatant] {
        if let activeEntry,
           let attacker = attacker(for: activeEntry) {
            return [attacker] + defenders(for: activeEntry)
        }
        guard isPreparingSurprise else { return [] }
        return entries.compactMap(attacker(for:))
    }

    /// A generic master roll always belongs to a non-player combatant. A
    /// character-linked roll can still resolve more precisely before this
    /// fallback is used.
    public var masterRollRecipientCombatantId: UUID? {
        let eligible = rollEligibleCombatants
        if let rollRecipientCombatantId,
           eligible.contains(where: {
               $0.id == rollRecipientCombatantId && !$0.isPlayer
           }) {
            return rollRecipientCombatantId
        }
        guard activeAttackerId != nil else { return nil }
        return eligible.first(where: { !$0.isPlayer })?.id
    }

    public func combatant(id: UUID) -> BattleCombatant? {
        combatantIndexById[id].map { combatants[$0] }
    }

    public func combatant(pinId: UUID) -> BattleCombatant? {
        combatantIndexByPinId[pinId].map { combatants[$0] }
    }

    private func rebuildCombatantIndex() {
        // Last-wins rather than a trapping uniqueKeysWithValues — id and pinId
        // uniqueness is a roster invariant enforced by callers (addCombatant,
        // synchronize's additionalDefenders merge), not a type guarantee, and a
        // roster decoded from a peer can break it. See CODE_AUDIT_21 §6.8.
        combatantIndexById = Dictionary(
            combatants.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { _, new in new }
        )
        combatantIndexByPinId = Dictionary(
            combatants.enumerated().map { ($0.element.pinId, $0.offset) },
            uniquingKeysWith: { _, new in new }
        )
    }

    public func attacker(for entry: BattleRoundEntry) -> BattleCombatant? {
        combatant(id: entry.attackerId)
    }

    public func defenders(for entry: BattleRoundEntry) -> [BattleCombatant] {
        entry.defenderIds.compactMap(combatant(id:))
    }

    /// Whether the combatant has its own turn. A pin that was only ever
    /// highlighted as a target is on the roster without one.
    public func hasTurn(_ combatantId: UUID) -> Bool {
        entries.contains { $0.attackerId == combatantId }
    }

    /// Whether the pin can still get its own turn: only while the surprise
    /// round is being prepared, and only if it does not have one already.
    public func canAddCombatant(pinId: UUID) -> Bool {
        guard isPreparingSurprise else { return false }
        guard let existing = combatant(pinId: pinId) else { return true }
        return !hasTurn(existing.id)
    }

    // MARK: - Shared helpers

    /// Sorts the whole turn list by initiative. Used when a battle begins and
    /// when the initiative order changes; a single initiative edit goes
    /// through `repositionEntry(for:)` so a manually dragged order survives.
    func sortEntries() {
        let priorOrder = Dictionary(entries.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        entries.sort { lhs, rhs in
            let left = combatant(id: lhs.attackerId)?.initiative
            let right = combatant(id: rhs.attackerId)?.initiative
            if actsBefore(left, right) { return true }
            if actsBefore(right, left) { return false }
            return (priorOrder[lhs.id] ?? 0) < (priorOrder[rhs.id] ?? 0)
        }
    }

    /// Moves only this combatant's entry to where its initiative puts it and
    /// leaves every other entry where it is, so the order the game master
    /// dragged the other cards into is kept. The entry stays in place when it
    /// already fits between its neighbours (which also keeps ties stable).
    func repositionEntry(for combatantId: UUID) {
        guard let index = entries.firstIndex(where: { $0.attackerId == combatantId }) else { return }
        let initiative = combatant(id: combatantId)?.initiative
        let fitsAfterPrevious = index == 0
            || !actsBefore(initiative, initiativeOfEntry(at: index - 1))
        let fitsBeforeNext = index == entries.count - 1
            || !actsBefore(initiativeOfEntry(at: index + 1), initiative)
        guard !(fitsAfterPrevious && fitsBeforeNext) else { return }

        let entry = entries.remove(at: index)
        let destination = entries.firstIndex { other in
            actsBefore(initiative, combatant(id: other.attackerId)?.initiative)
        } ?? entries.count
        entries.insert(entry, at: destination)
    }

    private func initiativeOfEntry(at index: Int) -> Int? {
        combatant(id: entries[index].attackerId)?.initiative
    }

    /// `true` when `lhs` strictly comes before `rhs` in the current initiative
    /// order. A missing initiative comes after every value; equal values and
    /// two missing ones are ties.
    private func actsBefore(_ lhs: Int?, _ rhs: Int?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            initiativeOrder == .ascending ? lhs < rhs : lhs > rhs
        case (.some, .none):
            true
        case (.none, _):
            false
        }
    }

    func retentionKey(for combatant: BattleCombatant) -> UUID {
        combatant.sourceCharacterId ?? combatant.pinId
    }

    func bumpNetworkSequence() {
        networkSequence += 1
    }
}
