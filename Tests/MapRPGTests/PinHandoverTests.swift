// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_24 §5.1: the pin of a Character changes id (table player, joining player,
/// companion) while a map is shown or a battle is running.
@MainActor
struct PinHandoverTests {
    private struct Fixture {
        let sut: GameController
        let map: MapModel
        let tablePlayerId: UUID
        let characterId: UUID
    }

    private func makeFixture(inBattle: Bool = false) async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let characterId = UUID()
        let tablePlayerId = UUID()
        let map = MapModel(id: UUID(), name: "A", entries: [])
        sut.setGame(item: map, itemId: map.id)
        sut.resetPlayerPins(for: [PlayerGameModel(id: tablePlayerId, type: .player, name: "Hero", characterId: characterId)])
        let live = sut.gameItem(for: map.id)
        // The table player's pin was moved, hurt and highlighted on this map.
        var pin = try #require(live.mapPins.first { $0.id == tablePlayerId })
        pin.location = CGPoint(x: 320, y: 240)
        pin.mapId = map.id
        pin.healthPercent = 0.5
        pin.isHighlighted = true
        pin.timeInterval = 5
        live.mapPins = [pin]
        if inBattle {
            let combatant = BattleCombatant(pin: pin, sourceCharacterId: characterId, gameCharacterId: characterId, initiative: 10)
            sut.battleRoundModel.begin(mapId: map.id, players: [combatant], roomCombatants: [], initiativeOrder: .descending)
        }
        return Fixture(sut: sut, map: live, tablePlayerId: tablePlayerId, characterId: characterId)
    }

    @Test("A joining player's pin takes the place and state of the table player's pin for the same Character")
    func joiningPlayerInheritsTablePlayerPin() async throws {
        let fixture = try await makeFixture()
        let joiningId = UUID()

        fixture.sut.resetPlayerPins(for: [PlayerGameModel(id: joiningId, type: .player, name: "Anna", characterId: fixture.characterId)])

        #expect(!fixture.map.mapPins.contains { $0.id == fixture.tablePlayerId })
        let pin = try #require(fixture.map.mapPins.first { $0.id == joiningId })
        #expect(pin.location == CGPoint(x: 320, y: 240))
        #expect(pin.mapId == fixture.map.id)
        #expect(pin.healthPercent == 0.5)
        #expect(pin.isHighlighted)
        #expect(pin.name == "Anna", "identity comes from the new player")
        #expect(pin.players == [joiningId])

        // The map sync keeps the carried position instead of moving the pin into a room.
        fixture.sut.synchronizePlayerPins(for: fixture.map.id)
        #expect(fixture.map.mapPins.first { $0.id == joiningId }?.location == CGPoint(x: 320, y: 240))
    }

    @Test("A pin for another Character does not inherit anything")
    func otherCharacterStartsFresh() async throws {
        let fixture = try await makeFixture()
        let joiningId = UUID()

        fixture.sut.resetPlayerPins(for: [
            PlayerGameModel(id: fixture.tablePlayerId, type: .player, name: "Hero", characterId: fixture.characterId),
            PlayerGameModel(id: joiningId, type: .player, name: "Anna", characterId: UUID())
        ])

        let pin = try #require(fixture.map.mapPins.first { $0.id == joiningId })
        #expect(pin.location == .zero)
        #expect(pin.healthPercent == nil)
        #expect(fixture.map.mapPins.contains { $0.id == fixture.tablePlayerId })
    }

    @Test("A running battle follows the handover: same combatant, turn and initiative, new pin")
    func battleFollowsHandover() async throws {
        let fixture = try await makeFixture(inBattle: true)
        let battle = fixture.sut.battleRoundModel
        let combatantId = try #require(battle.combatant(pinId: fixture.tablePlayerId)?.id)
        #expect(battle.nextRound())
        #expect(battle.activeAttackerId == combatantId)
        let joiningId = UUID()

        fixture.sut.resetPlayerPins(for: [PlayerGameModel(id: joiningId, type: .player, name: "Anna", characterId: fixture.characterId)])

        #expect(battle.combatants.map(\.id) == [combatantId])
        #expect(battle.combatant(pinId: fixture.tablePlayerId) == nil)
        let combatant = try #require(battle.combatant(pinId: joiningId))
        #expect(combatant.id == combatantId)
        #expect(combatant.initiative == 10)
        #expect(battle.activeAttackerId == combatantId, "the turn stays")
        #expect(battle.entries.map(\.attackerId) == [combatantId])
        #expect(battle.activePinId == joiningId)
    }

    @Test("A player who leaves a running battle takes their combatant and turn with them")
    func leavingPlayerDropsCombatant() async throws {
        let fixture = try await makeFixture(inBattle: true)
        let battle = fixture.sut.battleRoundModel
        let other = BattleCombatant(
            pin: MapPinModel(id: UUID(), name: "Goblin"), sourceCharacterId: nil, gameCharacterId: nil, initiative: 3
        )
        let heroId = try #require(battle.combatants.first?.id)
        battle.joinCombatant(other)
        #expect(battle.nextRound())
        #expect(battle.activeAttackerId == heroId)

        fixture.sut.resetPlayerPins(for: [])

        #expect(battle.combatants.map(\.id) == [other.id])
        #expect(battle.entries.map(\.attackerId) == [other.id])
        #expect(battle.activeAttackerId == other.id, "the turn passes on")
        // The player's initiative is kept for a later battle.
        #expect(battle.retainedPlayerInitiatives[fixture.characterId] == 10)
    }
}
#endif
