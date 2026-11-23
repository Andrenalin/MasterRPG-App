// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import CharacterRPG
@testable import MapRPG

/// "Hide Hidden Attackers" in the Battle Round settings: the pins the players
/// cannot see are left out of the list while the option is on. The roster, the
/// turn order and the pins themselves never change by it.
@MainActor
@Suite("Battle round hidden attackers")
struct BattleRoundHiddenAttackersTests {
    // MARK: - Setting

    @Test("The option is off by default and kept across launches")
    func settingIsPersisted() throws {
        // Given
        let suite = "BattleRoundHiddenAttackersTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = BattleRoundSettingsModel(defaults: defaults)
        #expect(!sut.hidesHiddenAttackers)

        // When
        sut.hidesHiddenAttackers = true

        // Then
        #expect(BattleRoundSettingsModel(defaults: defaults).hidesHiddenAttackers)

        // When
        sut.hidesHiddenAttackers = false

        // Then
        #expect(!BattleRoundSettingsModel(defaults: defaults).hidesHiddenAttackers)
    }

    // MARK: - Battle start

    @Test("Hidden pins of the room are on the roster at battle start, whatever the option says")
    func hiddenPinsStartInTheBattle() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true

        // When
        try #require(fixture.sut.startBattle(itemId: fixture.mapId))

        // Then: the option narrows the list, not the battle.
        let model = fixture.sut.battleRoundModel
        #expect(model.combatant(pinId: fixture.hiddenGoblin.id) != nil)
        #expect(model.entries.count == 3)
    }

    // MARK: - Hidden pins

    @Test("Nothing is left out while the option is off")
    func nothingIsHiddenWhileOff() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()

        // Then
        #expect(fixture.sut.battleHiddenPinIds().isEmpty)
        #expect(fixture.cards().map(\.attacker.combatant.pinId) == fixture.turnOrderPinIds)
    }

    @Test("A hidden attacker's card is dropped and the ranks count what is shown")
    func hiddenAttackerIsLeftOut() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true

        // When
        let cards = fixture.cards()

        // Then
        #expect(fixture.sut.battleHiddenPinIds() == [fixture.hiddenGoblin.id])
        #expect(cards.map(\.attacker.combatant.pinId) == [fixture.hero.id, fixture.visibleGoblin.id])
        #expect(cards.map(\.rank) == [1, 2])
    }

    @Test("The option changes neither the roster, the turn order nor any pin")
    func toggleLeavesTheBattleAlone() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        let model = fixture.sut.battleRoundModel
        let entriesBefore = model.entries
        let pinsBefore = fixture.map.mapPins

        // When
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        _ = fixture.cards()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = false

        // Then
        #expect(model.entries == entriesBefore)
        #expect(fixture.map.mapPins == pinsBefore)
        #expect(!(try #require(fixture.map.mapPins.first { $0.id == fixture.hiddenGoblin.id })).isShown)
        #expect(fixture.cards().map(\.attacker.combatant.pinId) == fixture.turnOrderPinIds)
    }

    @Test("A pin that is revealed later shows up, and one that is hidden later drops out")
    func followsRevealAndHide() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        #expect(!fixture.shownPinIds.contains(fixture.hiddenGoblin.id))

        // When: the hidden goblin is revealed.
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hiddenGoblin.id))

        // Then
        #expect(fixture.sut.battleHiddenPinIds().isEmpty)
        #expect(fixture.shownPinIds == fixture.turnOrderPinIds)

        // When: the visible goblin is hidden.
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.visibleGoblin.id))

        // Then
        #expect(fixture.sut.battleHiddenPinIds() == [fixture.visibleGoblin.id])
        #expect(fixture.shownPinIds == [fixture.hero.id, fixture.hiddenGoblin.id])
        #expect(fixture.cards().map(\.rank) == [1, 2])
    }

    @Test("A pin standing in a room that is not revealed counts as hidden")
    func pinInAnUnrevealedRoomIsHidden() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        #expect(fixture.sut.battleHiddenPinIds() == [fixture.hiddenGoblin.id])

        // When: the room is hidden again.
        #expect(fixture.sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.room.id))

        // Then: its pins are hidden, the player pin is not.
        #expect(fixture.sut.battleHiddenPinIds() == [fixture.hiddenGoblin.id, fixture.visibleGoblin.id])
        #expect(fixture.shownPinIds == [fixture.hero.id])
    }

    @Test("A hidden pin is left out of the other attackers' targets")
    func hiddenDefenderIsLeftOut() async throws {
        // Given: the hero has the turn and both goblins are targeted.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        let model = fixture.sut.battleRoundModel
        #expect(model.nextRound())
        for pinId in [fixture.hiddenGoblin.id, fixture.visibleGoblin.id] {
            fixture.sut.updatePinState(itemId: fixture.mapId, pinId: pinId) { $0.isHighlighted = true }
        }
        fixture.sut.synchronizeBattleDefenders(itemId: fixture.mapId, isGameMaster: true)
        let activeCard = try #require(fixture.cards().first { $0.isActive })
        #expect(Set(activeCard.defenders.map(\.combatant.pinId)) == [fixture.hiddenGoblin.id, fixture.visibleGoblin.id])

        // When
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true

        // Then
        let hiddenActiveCard = try #require(fixture.cards().first { $0.isActive })
        #expect(hiddenActiveCard.defenders.map(\.combatant.pinId) == [fixture.visibleGoblin.id])
    }

    // MARK: - Active attacker

    @Test("The header does not name an active attacker whose pin is hidden")
    func activeHiddenAttackerIsNotNamed() async throws {
        // Given: the turn reaches the hidden goblin.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        let model = fixture.sut.battleRoundModel
        #expect(model.nextRound())
        #expect(model.nextAttacker())

        // When / Then: the option is off, so the hidden goblin is named.
        #expect(model.activeAttackerName(hidingPins: fixture.sut.battleHiddenPinIds()) == "Hidden Goblin")
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        #expect(model.activeAttackerName(hidingPins: fixture.sut.battleHiddenPinIds()) == nil)

        // When: the next attacker is a visible one.
        #expect(model.nextAttacker())

        // Then
        #expect(model.activeAttackerName(hidingPins: fixture.sut.battleHiddenPinIds()) == "Visible Goblin")
    }

    // MARK: - Turn progression

    @Test("With the option on, the next turn passes over a hidden attacker and the round wraps around it")
    func nextTurnSkipsHiddenAttacker() async throws {
        // Given: order is hero, hidden goblin, visible goblin.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        let model = fixture.sut.battleRoundModel
        #expect(fixture.sut.nextBattleRound(itemId: fixture.mapId))
        #expect(model.activePinId == fixture.hero.id)

        // When / Then: the hidden goblin has no turn.
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))
        #expect(model.activePinId == fixture.visibleGoblin.id)
        #expect(model.roundCounter == 1)

        // When / Then: the round ends after the visible goblin, and the next one starts at the hero.
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))
        #expect(model.activePinId == fixture.hero.id)
        #expect(model.roundCounter == 2)
    }

    @Test("With the option off, a hidden attacker keeps its turn")
    func nextTurnKeepsHiddenAttackerWhileOff() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        let model = fixture.sut.battleRoundModel
        #expect(fixture.sut.nextBattleRound(itemId: fixture.mapId))

        // When
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))

        // Then
        #expect(model.activePinId == fixture.hiddenGoblin.id)
    }

    @Test("A new round starts at the first attacker that is not hidden")
    func nextRoundStartsAtFirstShownAttacker() async throws {
        // Given: the hero, first in the order, is hidden; the goblin of the room is revealed.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hero.id))
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hiddenGoblin.id))

        // When
        #expect(fixture.sut.nextBattleRound(itemId: fixture.mapId))

        // Then
        #expect(fixture.sut.battleRoundModel.activePinId == fixture.hiddenGoblin.id)
    }

    @Test("A pin revealed later gets its turn again, and one hidden during its turn passes it on")
    func turnFollowsRevealAndHide() async throws {
        // Given: the hero has the turn, the hidden goblin is skipped.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        let model = fixture.sut.battleRoundModel
        #expect(fixture.sut.nextBattleRound(itemId: fixture.mapId))

        // When: the goblin is revealed.
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hiddenGoblin.id))
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))

        // Then
        #expect(model.activePinId == fixture.hiddenGoblin.id)

        // When: it is hidden again during its turn.
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hiddenGoblin.id))
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))

        // Then
        #expect(model.activePinId == fixture.visibleGoblin.id)
    }

    @Test("When every attacker is hidden there is no turn to hand out, and nothing changes")
    func noTurnWhenEveryAttackerIsHidden() async throws {
        // Given: the room is closed and the hero is hidden.
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true
        let model = fixture.sut.battleRoundModel
        #expect(fixture.sut.nextBattleRound(itemId: fixture.mapId))
        #expect(fixture.sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.room.id))
        #expect(fixture.sut.togglePin(itemId: fixture.mapId, pinId: fixture.hero.id))
        let round = model.roundCounter
        let active = model.activeAttackerId

        // When / Then
        #expect(!fixture.sut.nextBattleAttacker(itemId: fixture.mapId))
        #expect(!fixture.sut.nextBattleRound(itemId: fixture.mapId))
        #expect(model.roundCounter == round)
        #expect(model.activeAttackerId == active)

        // When: the option is turned off, the battle goes on.
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = false

        // Then
        #expect(fixture.sut.nextBattleAttacker(itemId: fixture.mapId))
    }

    // MARK: - Without a battle

    @Test("No pins are left out without a running battle")
    func noBattleNoHiddenPins() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        fixture.sut.battleRoundSettings.hidesHiddenAttackers = true

        // Then
        #expect(fixture.sut.battleHiddenPinIds().isEmpty)
    }

    @Test("Hiding nothing returns every card unchanged")
    func emptyHiddenSetKeepsEveryCard() async throws {
        // Given
        let fixture = try await Fixture.make()
        defer { fixture.resetSetting() }
        try fixture.startBattle()
        let model = fixture.sut.battleRoundModel

        // Then
        #expect(model.cardPresentations(hidingPins: []) == model.cardPresentations)
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    let sut: MapRPG.GameController
    let mapId: UUID
    let room: MapEntryModel
    let hero: MapPinModel
    let hiddenGoblin: MapPinModel
    let visibleGoblin: MapPinModel

    var map: MapModel { sut.gameItem(for: mapId) }

    /// Initiative puts the hero first, the hidden goblin second and the
    /// visible goblin last.
    var turnOrderPinIds: [UUID] { [hero.id, hiddenGoblin.id, visibleGoblin.id] }

    /// The pins that are shown to the players right now, in turn order.
    var shownPinIds: [UUID] {
        let hidden = map.hiddenPinIds
        return turnOrderPinIds.filter { !hidden.contains($0) }
    }

    /// The setting lives in the standard defaults, shared by every test and the app that hosts
    /// them: a test that turns it on must not leave it on.
    func resetSetting() {
        sut.battleRoundSettings.hidesHiddenAttackers = false
    }

    func cards() -> [BattleRoundCardPresentation] {
        sut.battleRoundModel.cardPresentations(hidingPins: sut.battleHiddenPinIds())
    }

    func startBattle() throws {
        try #require(sut.startBattle(itemId: mapId))
        let model = sut.battleRoundModel
        for (pinId, initiative) in [(hero.id, 30), (hiddenGoblin.id, 20), (visibleGoblin.id, 10)] {
            let combatant = try #require(model.combatant(pinId: pinId))
            try #require(sut.setBattleInitiative(itemId: mapId, combatantId: combatant.id, value: initiative))
        }
        #expect(model.entries.compactMap { model.attacker(for: $0)?.pinId } == turnOrderPinIds)
    }

    /// One revealed room with a visible and a hidden goblin in it, and the
    /// hero outside of it.
    static func make() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
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
            isShown: true
        )
        let hero = MapPinModel(
            id: UUID(),
            name: "Hero",
            characterId: UUID(),
            location: CGPoint(x: 600, y: 50),
            isPlayer: true
        )
        let hiddenGoblin = MapPinModel(
            id: UUID(),
            name: "Hidden Goblin",
            location: CGPoint(x: 30, y: 50),
            isShown: false
        )
        let visibleGoblin = MapPinModel(
            id: UUID(),
            name: "Visible Goblin",
            location: CGPoint(x: 70, y: 50)
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room],
            mapPins: [hero, hiddenGoblin, visibleGoblin]
        )
        sut.battleRoundSettings.hidesHiddenAttackers = false
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        return Fixture(
            sut: sut,
            mapId: mapId,
            room: room,
            hero: hero,
            hiddenGoblin: hiddenGoblin,
            visibleGoblin: visibleGoblin
        )
    }
}
