// @copyright André Trettin

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

        // Then
        #expect(sut.combatant(id: first.id)?.initiative == 1)
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
        #expect(sut.rolls(for: attacker.id, in: entry).map(\.total) == [14, 7])
        #expect(sut.rolls(for: defender.id, in: entry).map(\.total) == [11])
        #expect(Set(entry.rolls.map(\.id)).count == 3)
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
        #expect(sut.rolls(for: player.id, in: playerEntry).map(\.total) == [14])
        #expect(sut.rolls(for: monster.id, in: monsterEntry).map(\.total) == [9])

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
        let decoded = try #require(BattleRoundNetworkState.decodeData(ended.encodeData()))
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

        #expect(settings.initiativeName == "Ini")
        #expect(settings.hitPointsName == "HP")
        #expect(settings.initiativeOrder == .descending)

        settings.initiativeName = "Speed"
        settings.hitPointsName = "Health"
        settings.initiativeOrder = .ascending

        let restored = BattleRoundSettingsModel(defaults: defaults)
        #expect(restored.initiativeName == "Speed")
        #expect(restored.hitPointsName == "Health")
        #expect(restored.initiativeOrder == .ascending)
    }

    private func combatant(
        name: String,
        initiative: Int? = nil,
        highlighted: Bool = false,
        sourceCharacterId: UUID? = UUID(),
        gameCharacterId: UUID? = UUID(),
        isPlayer: Bool = false,
        pinId: UUID = UUID()
    ) -> BattleCombatant {
        BattleCombatant(
            pin: MapPinModel(
                id: pinId,
                name: name,
                color: .blue,
                characterId: sourceCharacterId,
                isPlayer: isPlayer,
                isHighlighted: highlighted
            ),
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: gameCharacterId,
            initiative: initiative,
            isPlayer: isPlayer
        )
    }
}
