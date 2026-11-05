// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import CharacterRPG
@testable import MapRPG

/// Battle rules that span the map controller: who owns the initiative order,
/// how a pin is marked dead from the map, how a highlighted pin joins.
@MainActor
@Suite("Battle round map controller rules", .serialized)
struct BattleRoundControllerRuleTests {
    // MARK: - Initiative order

    @Test("An initiative order chosen before the first battle is used and kept")
    func orderChosenBeforeTheFirstBattle() async throws {
        // Given: no battle has run yet in this session.
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        let previousOrder = sut.battleRoundSettings.initiativeOrder
        defer { sut.setBattleInitiativeOrder(previousOrder) }
        sut.setBattleInitiativeOrder(.descending)
        #expect(sut.battleRoundModel.mapId == nil)

        // When: the game master switches the order, then starts the battle.
        #expect(sut.setBattleInitiativeOrder(.ascending))
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then: the battle runs ascending and the setting was not reverted.
        #expect(sut.battleRoundModel.initiativeOrder == .ascending)
        #expect(sut.battleRoundSettings.initiativeOrder == .ascending)

        let hero = try #require(sut.battleRoundModel.combatant(pinId: fixture.playerPinId))
        let goblin = try #require(sut.battleRoundModel.combatant(pinId: fixture.monsterPinId))
        #expect(sut.setBattleInitiative(itemId: fixture.mapId, combatantId: hero.id, value: 18))
        #expect(sut.setBattleInitiative(itemId: fixture.mapId, combatantId: goblin.id, value: 6))
        #expect(sut.battleRoundModel.entries.map(\.attackerId) == [goblin.id, hero.id])

        // When: the order changes during the battle.
        #expect(sut.setBattleInitiativeOrder(.descending))

        // Then: setting and turn list follow together.
        #expect(sut.battleRoundSettings.initiativeOrder == .descending)
        #expect(sut.battleRoundModel.entries.map(\.attackerId) == [hero.id, goblin.id])
        #expect(!sut.setBattleInitiativeOrder(.descending))
    }

    @Test("Initiative read from a Character value may be zero or negative")
    func initiativeFromAValueIsNotClamped() async throws {
        let sut = try await Fixture.make().controller

        #expect(sut.battleInitiative(from: " 0 ") == 0)
        #expect(sut.battleInitiative(from: "-3") == -3)
        #expect(sut.battleInitiative(from: "7.9") == 7)
        #expect(sut.battleInitiative(from: "-2.5") == -2)
        #expect(sut.battleInitiative(from: "fast") == nil)
        // Finite, but outside `Int`: must not trap.
        #expect(sut.battleInitiative(from: "9223372036854775808") == nil)
        #expect(sut.battleInitiative(from: "1e300") == nil)
    }

    // MARK: - Live map state

    @Test("The live map state is equal for an unchanged map and differs once a pin changes")
    func liveMapStateComparesByValue() async throws {
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        let before = sut.mapLiveState(for: fixture.mapId)

        // Two readings of one state are equal, which two encodings of the
        // map state message are not.
        #expect(sut.mapLiveState(for: fixture.mapId) == before)

        // The goblin sits in an unrevealed room, which the live state leaves out for players
        // (CODE_AUDIT_23 §6.1), so the visible dragon is the pin that changes it.
        #expect(sut.toggleDeadPin(itemId: fixture.mapId, pinId: fixture.outsidePinId))

        #expect(sut.mapLiveState(for: fixture.mapId) != before)
    }

    // MARK: - Dead from the map

    @Test("Marking a combatant dead from the map does the battle bookkeeping")
    func deadToggleFromTheMapUpdatesTheBattle() async throws {
        // Given: the hero attacks the highlighted goblin.
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        #expect(sut.startBattle(itemId: fixture.mapId))
        let hero = try #require(sut.battleRoundModel.combatant(pinId: fixture.playerPinId))
        let goblin = try #require(sut.battleRoundModel.combatant(pinId: fixture.monsterPinId))
        #expect(sut.activateBattleAttacker(itemId: fixture.mapId, combatantId: hero.id))
        #expect(sut.toggleHighlightPin(itemId: fixture.mapId, pinId: fixture.monsterPinId, isGameMaster: true))
        #expect(sut.battleRoundModel.activeEntry?.defenderIds == [goblin.id])

        // When: "Mark Dead" from the map's pin menu, not from the card.
        #expect(sut.toggleDeadPin(itemId: fixture.mapId, pinId: fixture.monsterPinId))

        // Then: the roster knows, and the goblin is nobody's target any more.
        #expect(sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].isDead)
        #expect(sut.battleRoundModel.combatant(id: goblin.id)?.isDead == true)
        #expect(!sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].isHighlighted)
        #expect(sut.battleRoundModel.activeEntry?.defenderIds.isEmpty == true)

        // When: toggled back.
        #expect(sut.toggleDeadPin(itemId: fixture.mapId, pinId: fixture.monsterPinId))

        // Then
        #expect(!sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].isDead)
        #expect(sut.battleRoundModel.combatant(id: goblin.id)?.isDead == false)
    }

    @Test("Marking a pin dead without a battle only writes the pin")
    func deadToggleOutsideABattle() async throws {
        let fixture = try await Fixture.make()
        let sut = fixture.controller

        #expect(sut.toggleDeadPin(itemId: fixture.mapId, pinId: fixture.monsterPinId))
        #expect(sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].isDead)
        #expect(sut.toggleDeadPin(itemId: fixture.mapId, pinId: fixture.monsterPinId))
        #expect(!sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].isDead)
        #expect(!sut.toggleDeadPin(itemId: fixture.mapId, pinId: UUID()))
    }

    // MARK: - Joining the surprise round

    @Test("A pin highlighted while the surprise round is prepared can still be added to the battle")
    func highlightedOutsiderCanBeAdded() async throws {
        // Given: the surprise round is open; the dragon stands outside the room.
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        #expect(sut.startBattle(itemId: fixture.mapId))
        #expect(sut.battleRoundModel.combatant(pinId: fixture.outsidePinId) == nil)

        // When: it is highlighted first — it joins the roster as a target.
        #expect(sut.toggleHighlightPin(itemId: fixture.mapId, pinId: fixture.outsidePinId, isGameMaster: true))
        let target = try #require(sut.battleRoundModel.combatant(pinId: fixture.outsidePinId))
        #expect(!sut.battleRoundModel.hasTurn(target.id))

        // Then: "add to battle" still works and keeps that combatant.
        #expect(sut.addBattleCombatant(itemId: fixture.mapId, pinId: fixture.outsidePinId))
        let added = try #require(sut.battleRoundModel.combatant(pinId: fixture.outsidePinId))
        #expect(added.id == target.id)
        #expect(added.gameCharacterId == target.gameCharacterId)
        #expect(sut.battleRoundModel.hasTurn(added.id))
        #expect(!sut.addBattleCombatant(itemId: fixture.mapId, pinId: fixture.outsidePinId))
    }

    @Test("The pin action adds a pin to the battle in round 1")
    func outsiderCanJoinInRoundOne() async throws {
        // Given: the surprise round is over, we are in round 1 and the dragon has no turn.
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        #expect(sut.startBattle(itemId: fixture.mapId))
        #expect(sut.nextBattleRound(itemId: fixture.mapId))
        #expect(sut.battleRoundModel.roundCounter == 1)
        #expect(!sut.addBattleCombatant(itemId: fixture.mapId, pinId: fixture.outsidePinId))
        #expect(sut.battleRoundModel.canJoinBattle(pinId: fixture.outsidePinId, on: fixture.mapId))
        let activeBefore = sut.battleRoundModel.activeAttackerId

        // When / Then: the action adds it with its own turn; the round goes on unchanged.
        #expect(sut.joinBattle(itemId: fixture.mapId, pinId: fixture.outsidePinId))
        let joined = try #require(sut.battleRoundModel.combatant(pinId: fixture.outsidePinId))
        #expect(sut.battleRoundModel.hasTurn(joined.id))
        #expect(sut.battleRoundModel.roundCounter == 1)
        #expect(sut.battleRoundModel.activeAttackerId == activeBefore)
        #expect(!sut.battleRoundModel.canJoinBattle(pinId: fixture.outsidePinId, on: fixture.mapId))
        #expect(!sut.joinBattle(itemId: fixture.mapId, pinId: fixture.outsidePinId))
    }

    @Test("The pin action also adds a pin during the surprise round, and not on another map")
    func outsiderCanJoinInSurpriseRound() async throws {
        let fixture = try await Fixture.make()
        let sut = fixture.controller
        #expect(!sut.joinBattle(itemId: fixture.mapId, pinId: fixture.outsidePinId))
        #expect(sut.startBattle(itemId: fixture.mapId))
        #expect(!sut.joinBattle(itemId: UUID(), pinId: fixture.outsidePinId))
        #expect(sut.joinBattle(itemId: fixture.mapId, pinId: fixture.outsidePinId))
        let joined = try #require(sut.battleRoundModel.combatant(pinId: fixture.outsidePinId))
        #expect(sut.battleRoundModel.hasTurn(joined.id))
    }

    // MARK: - Character assignment

    @Test("Assigning a Character uses the chosen one when the pin's own can no longer be copied")
    func assignmentPrefersTheChosenCharacter() async throws {
        // Given: the goblin pin points at a Character that does not exist, so
        // it entered the battle without a runtime Character.
        let fixture = try await Fixture.make(monsterHasCharacter: false)
        let sut = fixture.controller
        #expect(sut.startBattle(itemId: fixture.mapId))
        let goblin = try #require(sut.battleRoundModel.combatant(pinId: fixture.monsterPinId))
        #expect(goblin.gameCharacterId == nil)

        // When: the game master picks an existing Character for it.
        #expect(sut.assignBattleCharacter(
            itemId: fixture.mapId,
            combatantId: goblin.id,
            characterId: fixture.spareCharacterId
        ))

        // Then: a runtime copy of the chosen Character is linked.
        let assigned = try #require(sut.battleRoundModel.combatant(id: goblin.id))
        #expect(assigned.sourceCharacterId == fixture.spareCharacterId)
        let copyId = try #require(assigned.gameCharacterId)
        #expect(copyId != fixture.spareCharacterId)
        #expect(fixture.root.characterRoot.valueGameControllable.battleCharacterCopy(for: copyId) != nil)
        #expect(sut.gameItem(for: fixture.mapId)[MapPinId.id, fixture.monsterPinId].characterId == copyId)
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    let root: MapRootModel
    let mapId: UUID
    let playerPinId: UUID
    let monsterPinId: UUID
    let outsidePinId: UUID
    let spareCharacterId: UUID

    var controller: MapRPG.GameController { root.gameController }

    /// A map with one focused room holding the hero and a goblin, and a
    /// dragon outside the room.
    static func make(monsterHasCharacter: Bool = true) async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let mapId = UUID()
        let playerCharacterId = UUID()
        let monsterCharacterId = UUID()
        let outsideCharacterId = UUID()
        let spareCharacterId = UUID()

        var characters = [
            ValueModel(id: playerCharacterId, name: "Hero"),
            ValueModel(id: outsideCharacterId, name: "Dragon"),
            ValueModel(id: spareCharacterId, name: "Orc")
        ]
        if monsterHasCharacter {
            characters.append(ValueModel(id: monsterCharacterId, name: "Goblin"))
        }
        for character in characters {
            root.characterRoot.itemController.replace(model: character, isInsert: true)
        }

        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            focused: true
        )
        let playerPin = MapPinModel(
            id: UUID(),
            name: "Hero",
            characterId: playerCharacterId,
            location: CGPoint(x: 20, y: 20),
            isPlayer: true
        )
        let monsterPin = MapPinModel(
            id: UUID(),
            name: "Goblin",
            characterId: monsterCharacterId,
            location: CGPoint(x: 60, y: 60)
        )
        let outsidePin = MapPinModel(
            id: UUID(),
            name: "Dragon",
            characterId: outsideCharacterId,
            location: CGPoint(x: 400, y: 400)
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room],
            mapPins: [playerPin, monsterPin, outsidePin]
        )
        root.itemController.replace(model: map, isInsert: true)
        root.gameController.setGame(item: map.copy(), itemId: mapId)

        return Fixture(
            root: root,
            mapId: mapId,
            playerPinId: playerPin.id,
            monsterPinId: monsterPin.id,
            outsidePinId: outsidePin.id,
            spareCharacterId: spareCharacterId
        )
    }
}
