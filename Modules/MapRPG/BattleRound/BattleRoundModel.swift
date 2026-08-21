// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import SwiftUI

// Plain value types (BattleInitiativeOrder, BattleValueKind, BattleRollResult,
// BattleCombatant, BattleRoundEntry, BattleRoundNetworkState) now live in
// BattleRoundTypes.swift — see CODE_AUDIT §9.10.

@MainActor @Observable
public final class BattleRoundModel: Sendable {
    // MARK: - Combatant lookups

    public init() {}

    public private(set) var isRunning = false
    public private(set) var mapId: UUID?
    public private(set) var roundCounter = 0
    public var initiativeOrder: BattleInitiativeOrder = .descending
    public private(set) var combatants: [BattleCombatant] = []
    public private(set) var entries: [BattleRoundEntry] = []
    public private(set) var activeAttackerId: UUID?
    public private(set) var rollRecipientCombatantId: UUID?
    public private(set) var networkSequence = 0
    public private(set) var presentedActivePinId: UUID?

    /// Player initiative is retained when a battle closes. Room combatants are
    /// rebuilt for every new battle so the next activated room supplies a fresh
    /// group of monster instances.
    private var retainedPlayerInitiatives: [UUID: Int] = [:]
    private var retainedPlayerCombatants: [UUID: BattleCombatant] = [:]

    /// Backing store for `cardPresentations` (see `BattleRoundCardPresentation.swift`).
    /// A stored property can only live on the type's own declaration, not on
    /// the extension that defines the computed property itself, which is why
    /// it's declared here rather than alongside `cardPresentations`. See
    /// CODE_AUDIT §7.2.
    var cardPresentationsCache: (key: CardPresentationsCacheKey, value: [BattleRoundCardPresentation])?

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
        combatants.first { $0.id == id }
    }

    public func combatant(pinId: UUID) -> BattleCombatant? {
        combatants.first { $0.pinId == pinId }
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

    // MARK: - Roster mutation

    @discardableResult
    func addCombatant(_ combatant: BattleCombatant) -> Bool {
        guard isPreparingSurprise,
              self.combatant(pinId: combatant.pinId) == nil else {
            return false
        }
        combatants.append(combatant)
        entries.append(BattleRoundEntry(attackerId: combatant.id))
        if combatant.isPlayer {
            retainedPlayerCombatants[combatant.pinId] = combatant
        }
        sortEntries()
        return true
    }

    /// Drops a combatant from the battle entirely — its own turn entry and
    /// every appearance as another entry's defender — rather than just
    /// flagging it dead. The map pin itself is untouched, so highlighting it
    /// again re-adds it as a fresh combatant.
    @discardableResult
    func removeCombatant(_ combatantId: UUID) -> Bool {
        guard let combatant = combatant(id: combatantId) else { return false }
        combatants.removeAll { $0.id == combatantId }
        entries.removeAll { $0.attackerId == combatantId }
        for index in entries.indices {
            entries[index].defenderIds.removeAll { $0 == combatantId }
        }
        if activeAttackerId == combatantId {
            activeAttackerId = nil
            presentedActivePinId = nil
        }
        if rollRecipientCombatantId == combatantId {
            rollRecipientCombatantId = nil
        }
        if combatant.isPlayer {
            retainedPlayerCombatants.removeValue(forKey: combatant.pinId)
            retainedPlayerInitiatives.removeValue(forKey: retentionKey(for: combatant))
        }
        bumpNetworkSequence()
        return true
    }

    // MARK: - Battle lifecycle

    func begin(
        mapId: UUID,
        players: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) {
        rememberPlayerInitiatives()
        self.mapId = mapId
        self.initiativeOrder = initiativeOrder
        isRunning = true
        roundCounter = 0
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil

        let refreshedPlayers = players.map { incoming in
            guard var retained = retainedPlayerCombatants[incoming.pinId],
                  retained.sourceCharacterId == incoming.sourceCharacterId else {
                var newPlayer = incoming
                newPlayer.initiative = retainedPlayerInitiatives[retentionKey(for: incoming)]
                    ?? incoming.initiative
                retainedPlayerCombatants[incoming.pinId] = newPlayer
                return newPlayer
            }
            retained.pin = incoming.pin
            retained.initiative = retainedPlayerInitiatives[retentionKey(for: incoming)]
                ?? retained.initiative
                ?? incoming.initiative
            retainedPlayerCombatants[incoming.pinId] = retained
            return retained
        }

        let allCombatants = refreshedPlayers + roomCombatants
        combatants = allCombatants
        entries = allCombatants.map { BattleRoundEntry(attackerId: $0.id) }
        sortEntries()
        bumpNetworkSequence()
    }

    func end() {
        rememberPlayerInitiatives()
        isRunning = false
        roundCounter = 0
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil
        bumpNetworkSequence()
    }

    // MARK: - Initiative & value configuration

    @discardableResult
    func setInitiative(_ value: Int?, for combatantId: UUID) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        let normalized = value.map { max(1, $0) }
        guard combatants[index].initiative != normalized else { return false }
        combatants[index].initiative = normalized
        if combatants[index].isPlayer {
            retainedPlayerInitiatives[retentionKey(for: combatants[index])] = normalized
        }
        sortEntries()
        return true
    }

    @discardableResult
    func adjustInitiative(by amount: Int, for combatantId: UUID) -> Bool {
        guard let combatant = combatant(id: combatantId) else { return false }
        return setInitiative(max(1, (combatant.initiative ?? 1) + amount), for: combatantId)
    }

    @discardableResult
    func setInitiativeOrder(_ order: BattleInitiativeOrder) -> Bool {
        guard initiativeOrder != order else { return false }
        initiativeOrder = order
        sortEntries()
        return true
    }

    @discardableResult
    func setValueEntry(
        _ entryId: UUID?,
        kind: BattleValueKind,
        for combatantId: UUID
    ) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        switch kind {
        case .initiative:
            guard combatants[index].initiativeEntryId != entryId else { return false }
            combatants[index].initiativeEntryId = entryId
        case .hitPoints:
            guard combatants[index].hitPointsEntryId != entryId else { return false }
            combatants[index].hitPointsEntryId = entryId
        }
        if combatants[index].isPlayer {
            retainedPlayerCombatants[combatants[index].pinId] = combatants[index]
        }
        return true
    }

    func moveEntries(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Turn progression

    @discardableResult
    func activateAttacker(_ combatantId: UUID) -> Bool {
        guard isRunning,
              entries.contains(where: { $0.attackerId == combatantId }),
              activeAttackerId != combatantId else {
            return false
        }
        activeAttackerId = combatantId
        rollRecipientCombatantId = combatantId
        presentedActivePinId = combatant(id: combatantId)?.pinId
        bumpNetworkSequence()
        return true
    }

    @discardableResult
    func nextAttacker() -> Bool {
        guard isRunning, !entries.isEmpty else { return false }
        guard let activeAttackerId,
              let index = entries.firstIndex(where: { $0.attackerId == activeAttackerId }) else {
            return activateAttacker(firstLivingAttackerId(from: 0) ?? entries[0].attackerId)
        }
        if let nextId = firstLivingAttackerId(from: index + 1) {
            return activateAttacker(nextId)
        }
        // Nobody alive remains later in this round's order: advance the round
        // and search again from the top, so a fallen combatant is skipped
        // there too instead of ending up active again.
        roundCounter += 1
        let firstId = firstLivingAttackerId(from: 0) ?? entries[0].attackerId
        self.activeAttackerId = firstId
        rollRecipientCombatantId = firstId
        presentedActivePinId = combatant(id: firstId)?.pinId
        bumpNetworkSequence()
        return true
    }

    /// The id of the first entry's attacker at or after `startIndex` who
    /// isn't dead. `nil` when nobody in that range is alive (e.g. everyone
    /// remaining in the round has fallen).
    private func firstLivingAttackerId(from startIndex: Int) -> UUID? {
        guard startIndex < entries.count else { return nil }
        for index in startIndex..<entries.count {
            guard let attacker = attacker(for: entries[index]), !attacker.isDead else { continue }
            return entries[index].attackerId
        }
        return nil
    }

    @discardableResult
    func nextRound() -> Bool {
        guard isRunning else { return false }
        roundCounter += 1
        activeAttackerId = entries.first?.attackerId
        rollRecipientCombatantId = activeAttackerId
        presentedActivePinId = activeAttackerId.flatMap { combatant(id: $0)?.pinId }
        bumpNetworkSequence()
        return true
    }

    @discardableResult
    func synchronize(
        pins: [MapPinModel],
        additionalDefenders: [BattleCombatant] = []
    ) -> Bool {
        guard isRunning else { return false }
        var changed = false
        let pinsById = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })

        for index in combatants.indices {
            guard let pin = pinsById[combatants[index].pinId], combatants[index].pin != pin else {
                continue
            }
            combatants[index].pin = pin
            changed = true
        }

        for defender in additionalDefenders where combatant(pinId: defender.pinId) == nil {
            combatants.append(defender)
            changed = true
        }

        guard let activeAttackerId,
              let entryIndex = entries.firstIndex(where: { $0.attackerId == activeAttackerId }),
              let attacker = combatant(id: activeAttackerId) else {
            return changed
        }

        let defenderIds = combatants
            .filter { $0.id != activeAttackerId && $0.isHighlighted }
            .map(\.id)
        if entries[entryIndex].defenderIds != defenderIds {
            entries[entryIndex].defenderIds = defenderIds
            changed = true
        }
        if let rollRecipientCombatantId,
           rollRecipientCombatantId != activeAttackerId,
           !defenderIds.contains(rollRecipientCombatantId) {
            self.rollRecipientCombatantId = activeAttackerId
            changed = true
        }

        // The active attacker is never a defender and must remain highlighted.
        if !attacker.isHighlighted {
            changed = true
        }
        return changed
    }

    // MARK: - Rolls

    @discardableResult
    func addRoll(
        combatantId: UUID,
        total: Int,
        expression: String?,
        timestamp: Date = .now
    ) -> Bool {
        let entryIndex: Int
        if let activeAttackerId,
           let activeIndex = entries.firstIndex(where: { $0.attackerId == activeAttackerId }) {
            let entry = entries[activeIndex]
            guard combatantId == activeAttackerId
                    || entry.defenderIds.contains(combatantId) else {
                return false
            }
            entryIndex = activeIndex
        } else {
            guard isPreparingSurprise,
                  let surpriseIndex = entries.firstIndex(where: {
                      $0.attackerId == combatantId
                  }) else {
                return false
            }
            entryIndex = surpriseIndex
        }
        entries[entryIndex].rolls.append(
            BattleRollResult(
                combatantId: combatantId,
                total: total,
                expression: expression,
                timestamp: timestamp
            )
        )
        return true
    }

    @discardableResult
    func selectRollRecipient(_ combatantId: UUID) -> Bool {
        if isPreparingSurprise {
            guard combatant(id: combatantId)?.isPlayer == false,
                  entries.contains(where: { $0.attackerId == combatantId }),
                  rollRecipientCombatantId != combatantId else {
                return false
            }
            rollRecipientCombatantId = combatantId
            return true
        }
        guard let activeAttackerId,
              let entry = activeEntry,
              combatant(id: combatantId)?.isPlayer == false,
              combatantId == activeAttackerId || entry.defenderIds.contains(combatantId),
              rollRecipientCombatantId != combatantId else {
            return false
        }
        rollRecipientCombatantId = combatantId
        return true
    }

    // MARK: - Network sync

    @discardableResult
    func applyRemoteState(_ state: BattleRoundNetworkState) -> Bool {
        guard state.sequence > networkSequence else { return false }
        mapId = state.mapId
        isRunning = state.isRunning
        roundCounter = state.roundCounter
        networkSequence = state.sequence
        presentedActivePinId = state.activePinId
        activeAttackerId = state.activePinId.flatMap { combatant(pinId: $0)?.id }
        rollRecipientCombatantId = activeAttackerId
        return true
    }

    func networkState() -> BattleRoundNetworkState? {
        guard let mapId else { return nil }
        return BattleRoundNetworkState(
            mapId: mapId,
            isRunning: isRunning,
            roundCounter: roundCounter,
            activePinId: activePinId,
            sequence: networkSequence
        )
    }

    // MARK: - Private helpers

    private func sortEntries() {
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

    private func rememberPlayerInitiatives() {
        for combatant in combatants where combatant.isPlayer {
            retainedPlayerCombatants[combatant.pinId] = combatant
            retainedPlayerInitiatives[retentionKey(for: combatant)] = combatant.initiative
        }
    }

    private func retentionKey(for combatant: BattleCombatant) -> UUID {
        combatant.sourceCharacterId ?? combatant.pinId
    }

    private func bumpNetworkSequence() {
        networkSequence += 1
    }

    // MARK: - Character assignment & reset

    func retainedGameCharacterId(
        forPlayerPinId pinId: UUID,
        sourceCharacterId: UUID?
    ) -> UUID? {
        guard let retained = retainedPlayerCombatants[pinId],
              retained.sourceCharacterId == sourceCharacterId else {
            return nil
        }
        return retained.gameCharacterId
    }

    @discardableResult
    func assignCharacter(
        combatantId: UUID,
        sourceCharacterId: UUID,
        gameCharacterId: UUID,
        pin: MapPinModel
    ) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        guard combatants[index].sourceCharacterId != sourceCharacterId
                || combatants[index].gameCharacterId != gameCharacterId
                || combatants[index].pin != pin else {
            return false
        }
        combatants[index].sourceCharacterId = sourceCharacterId
        combatants[index].gameCharacterId = gameCharacterId
        combatants[index].pin = pin
        if combatants[index].isPlayer {
            retainedPlayerCombatants[pin.id] = combatants[index]
        }
        return true
    }

    func reset() {
        isRunning = false
        mapId = nil
        roundCounter = 0
        combatants = []
        entries = []
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil
        networkSequence = 0
        retainedPlayerInitiatives = [:]
        retainedPlayerCombatants = [:]
    }
}
