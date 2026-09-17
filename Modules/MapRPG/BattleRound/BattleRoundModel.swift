// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

// Plain value types (BattleInitiativeOrder, BattleValueKind, BattleRollResult,
// BattleCombatant, BattleRoundEntry, BattleRoundNetworkState) now live in
// BattleRoundTypes.swift — see CODE_AUDIT §9.10.
//
// Split out of this file — see CODE_AUDIT §9.13:
// - BattleRoundModel+Roster.swift: roster mutation, character assignment, reset
// - BattleRoundModel+Turns.swift: battle lifecycle, initiative/value config, turn progression, synchronize
// - BattleRoundModel+Rolls.swift: rolls
// - BattleRoundModel+Network.swift: network sync
//
// `sortEntries`/`retentionKey(for:)`/`bumpNetworkSequence`/
// `retainedPlayer*` below are internal rather than `private` so those files
// can reach them — Swift's `private` only extends to same-file extensions.

@MainActor @Observable
public final class BattleRoundModel: Sendable {
    // MARK: - Combatant lookups

    public init() {}

    // `internal(set)` rather than `private(set)`: mutated from
    // BattleRoundModel+Roster.swift/+Turns.swift/+Network.swift now that this
    // class is split across files — see CODE_AUDIT §9.13.
    public internal(set) var isRunning = false
    public internal(set) var mapId: UUID?
    public internal(set) var roundCounter = 0
    public var initiativeOrder: BattleInitiativeOrder = .descending
    /// `combatant(id:)`/`combatant(pinId:)` are called from the live render
    /// path (one per pin, every canvas redraw during a battle — see
    /// `MapPinContentView` in `MapPinView.swift`), so a linear scan here
    /// becomes effectively O(n²) per redraw. `didSet` keeps the index
    /// dictionaries below in sync with every mutation, including in-place
    /// element writes like `combatants[index].pin = pin`. See CODE_AUDIT §7.1.
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
    /// it's declared here rather than alongside `cardPresentations`. See
    /// CODE_AUDIT §7.2.
    var cardPresentationsCache: (key: CardPresentationsCacheKey, value: [BattleRoundCardPresentation])?

    private var combatantIndexById: [UUID: Int] = [:]
    private var combatantIndexByPinId: [UUID: Int] = [:]

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
        combatantIndexById = Dictionary(
            uniqueKeysWithValues: combatants.enumerated().map { ($0.element.id, $0.offset) }
        )
        // Last-wins rather than a trapping uniqueKeysWithValues — pinId
        // uniqueness is a roster invariant enforced by callers (addCombatant,
        // synchronize's additionalDefenders merge), not a type guarantee.
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

    public func rolls(for combatantId: UUID, in entry: BattleRoundEntry) -> [BattleRollResult] {
        entry.rolls.filter { $0.combatantId == combatantId }
    }

    // MARK: - Shared private helpers

    func sortEntries() {
        let priorOrder = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        entries.sort { lhs, rhs in
            let left = combatant(id: lhs.attackerId)?.initiative
            let right = combatant(id: rhs.attackerId)?.initiative
            switch (left, right) {
            case let (.some(left), .some(right)) where left != right:
                return initiativeOrder == .ascending ? left < right : left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return (priorOrder[lhs.id] ?? 0) < (priorOrder[rhs.id] ?? 0)
            }
        }
    }

    func retentionKey(for combatant: BattleCombatant) -> UUID {
        combatant.sourceCharacterId ?? combatant.pinId
    }

    func bumpNetworkSequence() {
        networkSequence += 1
    }
}
