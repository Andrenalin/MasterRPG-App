// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import os
import SwiftUI
import Testing

@testable import MapRPG

/// The turn-order rules of `BattleRoundModel`: manual order, initiative
/// range, who gets the turn when the roster changes.
@MainActor
@Suite("Battle round turn order")
struct BattleRoundTurnOrderTests {
    // MARK: - Manual order

    @Test("A dragged card keeps its place when another combatant's initiative changes")
    func draggedOrderSurvivesOtherInitiativeEdits() {
        // Given: sorted by initiative, then the slowest is dragged to the top.
        let sut = BattleRoundModel()
        let fast = combatant(name: "Fast", initiative: 20)
        let middle = combatant(name: "Middle", initiative: 12)
        let slow = combatant(name: "Slow", initiative: 4)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [middle, slow, fast], initiativeOrder: .descending)
        #expect(order(sut) == [fast.id, middle.id, slow.id])
        sut.moveEntries(from: IndexSet(integer: 2), to: 0)
        #expect(order(sut) == [slow.id, fast.id, middle.id])

        // When: someone else's initiative changes without leaving its place.
        #expect(sut.setInitiative(13, for: middle.id))

        // Then: the dragged card is still on top.
        #expect(order(sut) == [slow.id, fast.id, middle.id])

        // When: another combatant's initiative moves it past a neighbour.
        #expect(sut.setInitiative(25, for: middle.id))

        // Then: only that card moved.
        #expect(order(sut) == [middle.id, slow.id, fast.id])
    }

    @Test("Changing a dragged combatant's own initiative sorts it back in")
    func ownInitiativeEditRepositionsTheCard() {
        let sut = BattleRoundModel()
        let fast = combatant(name: "Fast", initiative: 20)
        let middle = combatant(name: "Middle", initiative: 12)
        let slow = combatant(name: "Slow", initiative: 4)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [fast, middle, slow], initiativeOrder: .descending)
        sut.moveEntries(from: IndexSet(integer: 2), to: 0)
        #expect(order(sut) == [slow.id, fast.id, middle.id])

        #expect(sut.setInitiative(5, for: slow.id))

        #expect(order(sut) == [fast.id, middle.id, slow.id])
    }

    @Test("Changing the initiative order sorts the whole list again")
    func orderChangeSortsEverything() {
        let sut = BattleRoundModel()
        let fast = combatant(name: "Fast", initiative: 20)
        let middle = combatant(name: "Middle", initiative: 12)
        let slow = combatant(name: "Slow", initiative: 4)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [fast, middle, slow], initiativeOrder: .descending)
        sut.moveEntries(from: IndexSet(integer: 2), to: 0)

        #expect(sut.setInitiativeOrder(.ascending))

        #expect(order(sut) == [slow.id, middle.id, fast.id])
    }

    @Test("Equal initiatives keep their order when one of them is set")
    func tiesStayStable() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 10)
        let second = combatant(name: "Second", initiative: 12)
        let third = combatant(name: "Third", initiative: 3)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, second, third], initiativeOrder: .descending)
        #expect(order(sut) == [second.id, first.id, third.id])

        // Second drops to First's initiative: it already stands before First.
        #expect(sut.setInitiative(10, for: second.id))

        #expect(order(sut) == [second.id, first.id, third.id])
    }

    // MARK: - Initiative range

    @Test("Initiative may be zero or negative, and an empty value steps from zero")
    func initiativeIsNotClamped() {
        let sut = BattleRoundModel()
        let empty = combatant(name: "Empty")
        let other = combatant(name: "Other")
        let valued = combatant(name: "Valued", initiative: 1)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [empty, other, valued], initiativeOrder: .descending)

        #expect(sut.adjustInitiative(by: 1, for: empty.id))
        #expect(sut.combatant(id: empty.id)?.initiative == 1)

        #expect(sut.adjustInitiative(by: -1, for: other.id))
        #expect(sut.combatant(id: other.id)?.initiative == -1)

        #expect(sut.setInitiative(0, for: valued.id))
        #expect(sut.combatant(id: valued.id)?.initiative == 0)
        #expect(sut.setInitiative(-7, for: valued.id))
        #expect(sut.combatant(id: valued.id)?.initiative == -7)

        // Sorted descending: 1, -1, -7.
        #expect(order(sut) == [empty.id, other.id, valued.id])
    }

    // MARK: - Turn hand-over

    @Test("Removing the active attacker passes the turn to the next living one")
    func removingActiveAttackerHandsTheTurnOn() {
        // Given: round 1, second has the turn; third is dead.
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 20)
        let second = combatant(name: "Second", initiative: 15)
        let third = combatant(name: "Third", initiative: 10, isDead: true)
        let fourth = combatant(name: "Fourth", initiative: 5)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, second, third, fourth], initiativeOrder: .descending)
        #expect(sut.nextRound())
        #expect(sut.nextAttacker())
        #expect(sut.activeAttackerId == second.id)

        // When
        #expect(sut.removeCombatant(second.id))

        // Then: the turn went on, it did not go back to the top.
        #expect(sut.activeAttackerId == fourth.id)
        #expect(sut.rollRecipientCombatantId == fourth.id)
        #expect(sut.presentedActivePinId == fourth.pinId)
        #expect(sut.roundCounter == 1)
        #expect(order(sut) == [first.id, third.id, fourth.id])
    }

    @Test("Removing the active attacker at the end of the order starts the next round")
    func removingLastActiveAttackerAdvancesTheRound() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 20)
        let last = combatant(name: "Last", initiative: 5)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, last], initiativeOrder: .descending)
        #expect(sut.nextRound())
        #expect(sut.nextAttacker())
        #expect(sut.activeAttackerId == last.id)

        #expect(sut.removeCombatant(last.id))

        #expect(sut.activeAttackerId == first.id)
        #expect(sut.roundCounter == 2)
    }

    @Test("Removing the active attacker in the surprise round does not reopen preparation")
    func removingActiveAttackerInRoundZeroKeepsTheBattleGoing() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 20)
        let second = combatant(name: "Second", initiative: 5)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, second], initiativeOrder: .descending)
        #expect(sut.activateAttacker(first.id))
        #expect(!sut.isPreparingSurprise)

        #expect(sut.removeCombatant(first.id))

        #expect(sut.activeAttackerId == second.id)
        #expect(!sut.isPreparingSurprise)
    }

    @Test("Removing the only living attacker leaves nobody active")
    func removingTheOnlyAttackerClearsTheTurn() {
        let sut = BattleRoundModel()
        let only = combatant(name: "Only", initiative: 20)
        let fallen = combatant(name: "Fallen", initiative: 5, isDead: true)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [only, fallen], initiativeOrder: .descending)
        #expect(sut.nextRound())
        #expect(sut.activeAttackerId == only.id)

        #expect(sut.removeCombatant(only.id))

        #expect(sut.activeAttackerId == nil)
        #expect(sut.presentedActivePinId == nil)
        #expect(sut.roundCounter == 1)
    }

    @Test("With every combatant fallen there is no next turn and no next round")
    func noTurnWithoutLivingAttackers() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 20, isDead: true)
        let second = combatant(name: "Second", initiative: 5, isDead: true)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, second], initiativeOrder: .descending)

        #expect(!sut.nextAttacker())
        #expect(!sut.nextRound())

        #expect(sut.activeAttackerId == nil)
        #expect(sut.roundCounter == 0)
    }

    // MARK: - Roster

    @Test("A pin highlighted during the surprise round can still be given its own turn")
    func highlightedPinCanStillBeAdded() throws {
        // Given: the surprise round is being prepared and a pin from outside
        // the battle gets highlighted — it joins the roster as a target.
        let sut = BattleRoundModel()
        let hero = combatant(name: "Hero", initiative: 12, isPlayer: true)
        let outsider = combatant(name: "Outsider", initiative: 15, highlighted: true)
        sut.begin(mapId: UUID(), players: [hero], roomCombatants: [], initiativeOrder: .descending)
        #expect(sut.synchronize(pins: [hero.pin, outsider.pin], additionalDefenders: [outsider]))
        #expect(sut.combatant(pinId: outsider.pinId) != nil)
        #expect(!sut.hasTurn(outsider.id))

        // Then: it is not locked out of the battle.
        #expect(sut.canAddCombatant(pinId: outsider.pinId))

        // When: the game master adds it. A second combatant built for the
        // same pin must not replace the one on the roster.
        let duplicate = BattleCombatant(pin: outsider.pin, sourceCharacterId: nil, gameCharacterId: nil)
        #expect(sut.addCombatant(duplicate))

        // Then: the roster member got the turn, sorted in by its initiative.
        #expect(sut.hasTurn(outsider.id))
        #expect(sut.combatants.count(where: { $0.pinId == outsider.pinId }) == 1)
        #expect(order(sut) == [outsider.id, hero.id])
        #expect(!sut.canAddCombatant(pinId: outsider.pinId))
        #expect(!sut.addCombatant(duplicate))
    }

    @Test("Nothing can be added once the surprise round is over")
    func addingEndsWithTheSurpriseRound() {
        let sut = BattleRoundModel()
        let hero = combatant(name: "Hero", initiative: 12, isPlayer: true)
        let late = combatant(name: "Late")
        sut.begin(mapId: UUID(), players: [hero], roomCombatants: [], initiativeOrder: .descending)
        #expect(sut.nextRound())

        #expect(!sut.canAddCombatant(pinId: late.pinId))
        #expect(!sut.addCombatant(late))
    }

    @Test("The pin action adds a pin in round 1 too, without moving the active turn")
    func joiningWorksInAnyRound() {
        let sut = BattleRoundModel()
        let hero = combatant(name: "Hero", initiative: 12, isPlayer: true)
        let goblin = combatant(name: "Goblin", initiative: 8)
        let late = combatant(name: "Late", initiative: 10)
        let mapId = UUID()
        sut.begin(mapId: mapId, players: [hero], roomCombatants: [goblin], initiativeOrder: .descending)
        #expect(sut.nextRound())
        #expect(sut.roundCounter == 1)
        let activeBefore = sut.activeAttackerId

        // The tap path stays closed, the action is open — on the battle's map only.
        #expect(!sut.canAddCombatant(pinId: late.pinId))
        #expect(sut.canJoinBattle(pinId: late.pinId, on: mapId))
        #expect(!sut.canJoinBattle(pinId: late.pinId, on: UUID()))
        #expect(!sut.addCombatant(late))

        #expect(sut.joinCombatant(late))
        #expect(order(sut) == [hero.id, late.id, goblin.id])
        #expect(sut.activeAttackerId == activeBefore)
        #expect(sut.roundCounter == 1)
        #expect(!sut.canJoinBattle(pinId: late.pinId, on: mapId))
        #expect(!sut.joinCombatant(late))
    }

    @Test("No pin can join a battle that is not running")
    func joiningNeedsARunningBattle() {
        let sut = BattleRoundModel()
        let late = combatant(name: "Late")
        #expect(!sut.canJoinBattle(pinId: late.pinId, on: nil))
        #expect(!sut.joinCombatant(late))
    }

    @Test("Synchronizing pins updates every changed combatant and both lookups")
    func synchronizeUpdatesEveryChangedCombatant() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 12)
        let second = combatant(name: "Second", initiative: 8)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [first, second], initiativeOrder: .descending)
        var firstPin = first.pin
        firstPin.isDead = true
        var secondPin = second.pin
        secondPin.isDead = true

        #expect(sut.synchronize(pins: [firstPin, secondPin]))
        #expect(sut.combatant(id: first.id)?.isDead == true)
        #expect(sut.combatant(pinId: second.pinId)?.isDead == true)

        // Unchanged pins change nothing.
        #expect(!sut.synchronize(pins: [firstPin, secondPin]))
    }

    // MARK: - Rolls

    @Test("A combatant keeps only its newest rolls per turn entry")
    func rollHistoryIsCapped() throws {
        let sut = BattleRoundModel()
        let attacker = combatant(name: "Attacker", initiative: 12)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [attacker], initiativeOrder: .descending)
        let limit = BattleRoundModel.maximumRollsPerCombatant

        for total in 1...(limit + 5) {
            #expect(sut.addRoll(combatantId: attacker.id, total: total, expression: nil))
        }

        let rolls = try #require(sut.entries.first).rolls
        #expect(rolls.count == limit)
        #expect(rolls.first?.total == 6)
        #expect(rolls.last?.total == limit + 5)
    }

    // MARK: - Observation

    @Test("Filling the card presentation cache does not invalidate its readers")
    func cardPresentationCacheIsNotObserved() {
        let sut = BattleRoundModel()
        let attacker = combatant(name: "Attacker", initiative: 12)
        sut.begin(mapId: UUID(), players: [], roomCombatants: [attacker], initiativeOrder: .descending)
        // `onChange` runs synchronously inside the mutation that triggers it.
        let invalidated = OSAllocatedUnfairLock(initialState: false)

        // A view body reading the cards.
        withObservationTracking {
            _ = sut.cardPresentations
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        // Another reader refills the cache.
        sut.cardPresentationsCache = nil
        _ = sut.cardPresentations
        #expect(!invalidated.withLock { $0 })

        // A real change still reaches the reader.
        #expect(sut.setInitiative(3, for: attacker.id))
        #expect(invalidated.withLock { $0 })
    }

    // MARK: - Helpers

    private func order(_ model: BattleRoundModel) -> [UUID] {
        model.entries.map(\.attackerId)
    }

    private func combatant(
        name: String,
        initiative: Int? = nil,
        highlighted: Bool = false,
        isPlayer: Bool = false,
        isDead: Bool = false
    ) -> BattleCombatant {
        let characterId = UUID()
        return BattleCombatant(
            pin: MapPinModel(
                id: UUID(),
                name: name,
                color: .blue,
                characterId: characterId,
                isPlayer: isPlayer,
                isDead: isDead,
                isHighlighted: highlighted
            ),
            sourceCharacterId: characterId,
            gameCharacterId: characterId,
            initiative: initiative,
            isPlayer: isPlayer
        )
    }
}
