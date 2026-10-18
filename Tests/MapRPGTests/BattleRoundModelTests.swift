// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Battle round model")
struct BattleRoundModelTests {
    @Test("Battle starts at surprise round and sorts nil initiative last")
    func startsAtSurpriseRoundAndSorts() throws {
        // Given
        let sut = BattleRoundModel()
        let low = combatant(name: "Low", initiative: 2)
        let high = combatant(name: "High", initiative: 18)
        let unset = combatant(name: "Unset")

        // When
        sut.begin(
            mapId: UUID(),
            players: [low],
            roomCombatants: [unset, high],
            initiativeOrder: .descending
        )

        // Then
        #expect(sut.isRunning)
        #expect(sut.roundCounter == 0)
        #expect(sut.activeAttackerId == nil)
        #expect(sut.entries.map(\.attackerId) == [high.id, low.id, unset.id])

        // When
        #expect(sut.nextRound())

        // Then
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == high.id)
    }

    @Test("Initiative supports ascending rules and quick adjustment")
    func initiativeOrderAndAdjustment() {
        // Given
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 8)
        let second = combatant(name: "Second", initiative: 3)
        sut.begin(
            mapId: UUID(),
            players: [first],
            roomCombatants: [second],
            initiativeOrder: .descending
        )

        // When
        #expect(sut.setInitiativeOrder(.ascending))

        // Then
        #expect(sut.entries.map(\.attackerId) == [second.id, first.id])

        // When
        #expect(sut.adjustInitiative(by: -20, for: first.id))

        // Then: initiative is not clamped; 0 and negative values are valid.
        #expect(sut.combatant(id: first.id)?.initiative == -12)
        #expect(sut.entries.first?.attackerId == first.id)
    }

    @Test("Next attacker follows initiative order and rolls over to the next round")
    func nextAttackerSequenceAndRoundRollover() throws {
        // Given
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12)
        let third = combatant(name: "Third", initiative: 4)
        sut.begin(
            mapId: UUID(),
            players: [second],
            roomCombatants: [third, first],
            initiativeOrder: .descending
        )

        // When: leaving the surprise round activates the first ordered entry.
        #expect(sut.nextRound())

        // Then
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == first.id)
        #expect(sut.rollRecipientCombatantId == first.id)

        // When / Then: each turn advances without changing the round.
        #expect(sut.nextAttacker())
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == second.id)
        #expect(sut.rollRecipientCombatantId == second.id)

        #expect(sut.nextAttacker())
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == third.id)

        // When: advancing after the final entry starts the next round.
        #expect(sut.nextAttacker())

        // Then
        #expect(sut.roundCounter == 2)
        #expect(sut.activeAttackerId == first.id)
        #expect(sut.rollRecipientCombatantId == first.id)
        let activeEntry = try #require(sut.activeEntry)
        #expect(activeEntry.attackerId == first.id)
    }

    @Test("Next attacker skips fallen combatants and rolls over when none remain alive")
    func nextAttackerSkipsDeadCombatants() throws {
        // Given: second is already dead when the round begins.
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12, isDead: true)
        let third = combatant(name: "Third", initiative: 4)
        sut.begin(
            mapId: UUID(),
            players: [second],
            roomCombatants: [third, first],
            initiativeOrder: .descending
        )
        #expect(sut.nextRound())
        #expect(sut.activeAttackerId == first.id)

        // When: advancing from first should skip the dead second entirely.
        #expect(sut.nextAttacker())

        // Then
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == third.id)

        // When: third was the last entry, and second (the only remaining
        // one) is dead, so the round rolls over and lands back on first.
        #expect(sut.nextAttacker())

        // Then
        #expect(sut.roundCounter == 2)
        #expect(sut.activeAttackerId == first.id)
        #expect(sut.rollRecipientCombatantId == first.id)
    }

    @Test("When the last living combatant falls, the turn and the round stay where they are")
    func nextAttackerStopsWhenAllDead() throws {
        // Given: first has the turn in round 1; second is already dead.
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12, isDead: true)
        sut.begin(
            mapId: UUID(),
            players: [second],
            roomCombatants: [first],
            initiativeOrder: .descending
        )
        #expect(sut.nextRound())
        #expect(sut.activeAttackerId == first.id)

        // When: first falls too, so nobody is alive to take a turn.
        var fallen = first.pin
        fallen.isDead = true
        #expect(sut.synchronize(pins: [fallen]))

        // Then: "Next Turn" and "Next Round" do nothing. They used to hand
        // the turn to a dead combatant and count a new round on every press.
        #expect(!sut.nextAttacker())
        #expect(!sut.nextRound())
        #expect(sut.roundCounter == 1)
        #expect(sut.activeAttackerId == first.id)
    }

    /// CODE_AUDIT_19 §5.8: `nextRound()` must skip a fallen first combatant like `nextAttacker()`.
    @Test("A new round skips a fallen first combatant")
    func nextRoundSkipsDeadFirstCombatant() {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18, isDead: true)
        let second = combatant(name: "Second", initiative: 12)
        sut.begin(mapId: UUID(), players: [second], roomCombatants: [first], initiativeOrder: .descending)

        #expect(sut.nextRound())

        #expect(sut.activeAttackerId == second.id)
        #expect(sut.rollRecipientCombatantId == second.id)
    }

    /// CODE_AUDIT_19 §5.8: a fallen combatant leaves every attacker's target list, not only the
    /// active one's.
    @Test("Removing a fallen defender clears it from every entry")
    func removeDefenderClearsEveryEntry() throws {
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12)
        let target = combatant(name: "Target", initiative: 4, highlighted: true)
        sut.begin(mapId: UUID(), players: [first, second], roomCombatants: [target], initiativeOrder: .descending)
        #expect(sut.activateAttacker(first.id))
        _ = sut.synchronize(pins: [first.pin, second.pin, target.pin])
        #expect(sut.activateAttacker(second.id))
        _ = sut.synchronize(pins: [first.pin, second.pin, target.pin])
        #expect(sut.entries.filter { $0.defenderIds.contains(target.id) }.count == 2)
        let sequence = sut.networkSequence

        #expect(sut.removeDefender(target.id))

        #expect(sut.entries.allSatisfy { !$0.defenderIds.contains(target.id) })
        #expect(sut.networkSequence > sequence)
        #expect(!sut.removeDefender(target.id))
    }

    @Test("Removing a combatant drops its own entry and every defender appearance")
    func removeCombatantDropsEntryAndDefenderReferences() throws {
        // Given: second is highlighted, so synchronizing while third is
        // active picks it up as a defender on third's entry.
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12, highlighted: true)
        let third = combatant(name: "Third", initiative: 4)
        sut.begin(
            mapId: UUID(),
            players: [second],
            roomCombatants: [third, first],
            initiativeOrder: .descending
        )
        #expect(sut.activateAttacker(third.id))
        #expect(sut.synchronize(pins: []))
        let thirdEntryId = try #require(sut.activeEntry).id
        #expect(try #require(sut.activeEntry).defenderIds.contains(second.id))

        // When: second — a defender on third's entry, not third itself — is
        // removed.
        #expect(sut.removeCombatant(second.id))

        // Then: second is gone entirely, and the surviving entry that
        // listed it as a defender no longer does. Third, untouched, is
        // still active.
        #expect(sut.combatant(id: second.id) == nil)
        #expect(Set(sut.entries.map(\.attackerId)) == Set([first.id, third.id]))
        let thirdEntry = try #require(sut.entries.first { $0.id == thirdEntryId })
        #expect(!thirdEntry.defenderIds.contains(second.id))
        #expect(sut.activeAttackerId == third.id)

        // When: the active attacker itself is removed.
        #expect(sut.removeCombatant(third.id))

        // Then: its own entry is gone too, and its turn passed on. Third was
        // last in the order, so first opens the next round.
        #expect(sut.combatant(id: third.id) == nil)
        #expect(sut.entries.map(\.attackerId) == [first.id])
        #expect(sut.activeAttackerId == first.id)
        #expect(sut.roundCounter == 1)

        // When: removing an id that no longer exists.
        // Then: it reports failure rather than silently succeeding.
        #expect(!sut.removeCombatant(third.id))
    }

    @Test("Manual initiative order becomes the turn sequence")
    func manualOrderDrivesTurnSequence() {
        // Given
        let sut = BattleRoundModel()
        let first = combatant(name: "First", initiative: 18)
        let second = combatant(name: "Second", initiative: 12)
        let third = combatant(name: "Third", initiative: 4)
        sut.begin(
            mapId: UUID(),
            players: [first],
            roomCombatants: [second, third],
            initiativeOrder: .descending
        )

        // When: the master moves the final card to the beginning.
        sut.moveEntries(from: IndexSet(integer: 2), to: 0)

        // Then: starting and advancing follows that visible manual order.
        #expect(sut.entries.map(\.attackerId) == [third.id, first.id, second.id])
        #expect(sut.nextRound())
        #expect(sut.activeAttackerId == third.id)
        #expect(sut.nextAttacker())
        #expect(sut.activeAttackerId == first.id)
    }

    @Test("Highlighted pins become defenders but the attacker never defends itself")
    func synchronizesDefendersWithoutSelf() throws {
        // Given
        let sut = BattleRoundModel()
        let attacker = combatant(name: "Attacker", highlighted: true)
        var defender = combatant(name: "Defender", highlighted: true)
        let idle = combatant(name: "Idle")
        sut.begin(
            mapId: UUID(),
            players: [attacker],
            roomCombatants: [defender, idle],
            initiativeOrder: .descending
        )
        #expect(sut.activateAttacker(attacker.id))

        // When
        #expect(sut.synchronize(pins: [attacker.pin, defender.pin, idle.pin]))

        // Then
        var active = try #require(sut.activeEntry)
        #expect(active.defenderIds == [defender.id])
        #expect(!active.defenderIds.contains(attacker.id))

        // When: a player's dehighlight removes the defender from this row.
        defender.pin.isHighlighted = false
        #expect(sut.synchronize(pins: [attacker.pin, defender.pin, idle.pin]))

        // Then
        active = try #require(sut.activeEntry)
        #expect(active.defenderIds.isEmpty)

        // When: the defender is restored and a new round starts.
        defender.pin.isHighlighted = true
        #expect(sut.synchronize(pins: [attacker.pin, defender.pin, idle.pin]))
        #expect(sut.nextRound())

        // Then: per-attacker defenders survive the round boundary.
        active = try #require(sut.activeEntry)
        #expect(active.defenderIds == [defender.id])
    }

    @Test("Multiple dice results are retained only for the active row participants")
    func recordsMultipleParticipantRolls() throws {
        // Given
        let sut = BattleRoundModel()
        let attacker = combatant(name: "Attacker", highlighted: true)
        let defender = combatant(name: "Defender", highlighted: true)
        let outsider = combatant(name: "Outsider")
        sut.begin(
            mapId: UUID(),
            players: [attacker],
            roomCombatants: [defender, outsider],
            initiativeOrder: .descending
        )
        #expect(sut.activateAttacker(attacker.id))
        #expect(sut.synchronize(pins: [attacker.pin, defender.pin, outsider.pin]))

        // When
        #expect(sut.addRoll(combatantId: attacker.id, total: 14, expression: "d20 + 2"))
        #expect(sut.addRoll(combatantId: attacker.id, total: 7, expression: "d8"))
        #expect(sut.addRoll(combatantId: defender.id, total: 11, expression: "d20"))
        #expect(!sut.addRoll(combatantId: outsider.id, total: 20, expression: "d20"))

        // Then
        let entry = try #require(sut.activeEntry)
        #expect(entry.rolls.filter { $0.combatantId == attacker.id }.map(\.total) == [14, 7])
        #expect(entry.rolls.filter { $0.combatantId == defender.id }.map(\.total) == [11])
        #expect(Set(entry.rolls.map(\.id)).count == 3)
    }

    @Test("A roll keeps its critical or fumble outcome, and an older payload without one still decodes")
    func rollOutcomeIsStoredAndOptionalOnTheWire() throws {
        // Given
        let sut = BattleRoundModel()
        let attacker = combatant(name: "Attacker", highlighted: true)
        sut.begin(mapId: UUID(), players: [attacker], roomCombatants: [], initiativeOrder: .descending)
        #expect(sut.activateAttacker(attacker.id))

        // When
        #expect(sut.addRoll(combatantId: attacker.id, total: 20, expression: "d20", outcome: .critical))
        #expect(sut.addRoll(combatantId: attacker.id, total: 1, expression: "d20", outcome: .fumble))
        #expect(sut.addRoll(combatantId: attacker.id, total: 9, expression: "d20"))

        // Then
        let entry = try #require(sut.activeEntry)
        #expect(entry.rolls.map(\.outcome) == [.critical, .fumble, nil])

        let roundTrip = try JSONDecoder().decode(
            BattleRollResult.self,
            from: JSONEncoder().encode(entry.rolls[0])
        )
        #expect(roundTrip == entry.rolls[0])

        // A roll encoded before `outcome` existed.
        let legacy = Data("""
        {"id":"\(UUID().uuidString)","combatantId":"\(attacker.id.uuidString)","total":14,"timestamp":0}
        """.utf8)
        let decoded = try JSONDecoder().decode(BattleRollResult.self, from: legacy)
        #expect(decoded.total == 14)
        #expect(decoded.outcome == nil)
    }

    @Test("Surprise accepts new combatants and records rolls on their own rows")
    func preparesSurpriseCombatantsAndRolls() throws {
        // Given
        let sut = BattleRoundModel()
        let player = combatant(name: "Player", isPlayer: true)
        let monster = combatant(name: "Monster")
        sut.begin(
            mapId: UUID(),
            players: [player],
            roomCombatants: [],
            initiativeOrder: .descending
        )

        // When / Then
        #expect(sut.isPreparingSurprise)
        #expect(sut.addCombatant(monster))
        #expect(!sut.addCombatant(monster))
        #expect(sut.entries.map(\.attackerId).contains(monster.id))
        #expect(sut.addRoll(combatantId: player.id, total: 14, expression: "d20"))
        #expect(sut.addRoll(combatantId: monster.id, total: 9, expression: "d20"))
        #expect(!sut.selectRollRecipient(player.id))
        #expect(sut.selectRollRecipient(monster.id))
        #expect(sut.masterRollRecipientCombatantId == monster.id)

        let playerEntry = try #require(sut.entries.first { $0.attackerId == player.id })
        let monsterEntry = try #require(sut.entries.first { $0.attackerId == monster.id })
        #expect(playerEntry.rolls.filter { $0.combatantId == player.id }.map(\.total) == [14])
        #expect(monsterEntry.rolls.filter { $0.combatantId == monster.id }.map(\.total) == [9])

        // Once a real round starts, the surprise roster is closed.
        #expect(sut.nextRound())
        #expect(!sut.isPreparingSurprise)
        #expect(!sut.addCombatant(combatant(name: "Late arrival")))
    }

    @Test("Player initiative and runtime identity survive closing while monsters refresh")
    func retainsPlayersAndRefreshesMonsters() throws {
        // Given
        let sut = BattleRoundModel()
        let sourceCharacterId = UUID()
        let gameCharacterId = UUID()
        let player = combatant(
            name: "Player",
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            isPlayer: true
        )
        let firstMonster = combatant(name: "Monster")
        let mapId = UUID()
        sut.begin(
            mapId: mapId,
            players: [player],
            roomCombatants: [firstMonster],
            initiativeOrder: .descending
        )
        #expect(sut.setInitiative(16, for: player.id))
        sut.end()

        // When
        let refreshedPlayer = combatant(
            name: "Player Updated",
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: UUID(),
            isPlayer: true,
            pinId: player.pinId
        )
        let secondMonster = combatant(name: "Monster")
        sut.begin(
            mapId: mapId,
            players: [refreshedPlayer],
            roomCombatants: [secondMonster],
            initiativeOrder: .descending
        )

        // Then
        let retainedPlayer = try #require(sut.combatant(pinId: player.pinId))
        #expect(retainedPlayer.id == player.id)
        #expect(retainedPlayer.gameCharacterId == gameCharacterId)
        #expect(retainedPlayer.initiative == 16)
        #expect(sut.combatant(id: firstMonster.id) == nil)
        #expect(sut.combatant(id: secondMonster.id) != nil)
    }

    @Test("Remote round state ignores stale sequence numbers")
    func rejectsStaleRemoteState() {
        // Given
        let sut = BattleRoundModel()
        let mapId = UUID()
        let current = BattleRoundNetworkState(
            mapId: mapId,
            isRunning: true,
            roundCounter: 3,
            activePinId: UUID(),
            sequence: 4
        )
        let stale = BattleRoundNetworkState(
            mapId: mapId,
            isRunning: true,
            roundCounter: 2,
            activePinId: nil,
            sequence: 3
        )

        // When / Then
        #expect(sut.applyRemoteState(current))
        #expect(!sut.applyRemoteState(stale))
        #expect(sut.roundCounter == 3)
        #expect(sut.activePinId == current.activePinId)
    }

    @Test("Newer remote end state clears presentation and survives a wire round trip")
    func appliesSequencedRemoteEndState() throws {
        // Given
        let sut = BattleRoundModel()
        let mapId = UUID()
        let running = BattleRoundNetworkState(
            mapId: mapId,
            isRunning: true,
            roundCounter: 2,
            activePinId: UUID(),
            sequence: 7
        )
        let ended = BattleRoundNetworkState(
            mapId: mapId,
            isRunning: false,
            roundCounter: 0,
            activePinId: nil,
            sequence: 8
        )
        #expect(sut.applyRemoteState(running))

        // When
        let decoded = try #require(BattleRoundNetworkState.decodeData(of: ended.encodeData()))
        #expect(sut.applyRemoteState(decoded))

        // Then
        #expect(decoded == ended)
        #expect(!sut.isRunning)
        #expect(sut.roundCounter == 0)
        #expect(sut.activePinId == nil)
        #expect(sut.networkSequence == ended.sequence)

        // An equal-sequence replay is not a new authoritative transition.
        #expect(!sut.applyRemoteState(decoded))
    }

    @Test("Battle value mappings are retained for player combatants")
    func retainsPlayerValueMappings() throws {
        let sut = BattleRoundModel()
        let player = combatant(name: "Player", isPlayer: true)
        let initiativeEntryId = UUID()
        let hitPointsEntryId = UUID()
        let mapId = UUID()
        sut.begin(
            mapId: mapId,
            players: [player],
            roomCombatants: [],
            initiativeOrder: .descending
        )

        #expect(sut.setValueEntry(initiativeEntryId, kind: .initiative, for: player.id))
        #expect(sut.setValueEntry(hitPointsEntryId, kind: .hitPoints, for: player.id))
        sut.end()
        sut.begin(
            mapId: mapId,
            players: [player],
            roomCombatants: [],
            initiativeOrder: .descending
        )

        let retained = try #require(sut.combatant(id: player.id))
        #expect(retained.initiativeEntryId == initiativeEntryId)
        #expect(retained.hitPointsEntryId == hitPointsEntryId)
    }

    @Test("Battle settings persist names and initiative order")
    func settingsPersist() throws {
        let suiteName = "BattleRoundModelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = BattleRoundSettingsModel(defaults: defaults)

        #expect(settings.initiativeNames == ["Ini"])
        #expect(settings.hitPointsNames == ["HP"])
        #expect(settings.initiativeOrder == .descending)

        settings.initiativeNames = ["Speed"]
        settings.hitPointsNames = ["Health"]
        settings.initiativeOrder = .ascending

        let restored = BattleRoundSettingsModel(defaults: defaults)
        #expect(restored.initiativeNames == ["Speed"])
        #expect(restored.hitPointsNames == ["Health"])
        #expect(restored.initiativeOrder == .ascending)
    }

    private func combatant(
        name: String,
        initiative: Int? = nil,
        highlighted: Bool = false,
        sourceCharacterId: UUID? = UUID(),
        gameCharacterId: UUID? = UUID(),
        isPlayer: Bool = false,
        isDead: Bool = false,
        pinId: UUID = UUID()
    ) -> BattleCombatant {
        BattleCombatant(
            pin: MapPinModel(
                id: pinId,
                name: name,
                color: .blue,
                characterId: sourceCharacterId,
                isPlayer: isPlayer,
                isDead: isDead,
                isHighlighted: highlighted
            ),
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            initiative: initiative,
            isPlayer: isPlayer
        )
    }
}
