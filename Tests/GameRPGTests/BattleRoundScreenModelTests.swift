// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG

/// The battle round screen's presentation rules: which list is open for what,
/// when a pending choice ends, when the screen closes, and how cards move.
@MainActor
@Suite("Battle round screen model")
struct BattleRoundScreenModelTests {
    // MARK: - Pending selection

    @Test("Choosing a value opens the list for that combatant, and cancelling goes back to all Characters")
    func choosingAValueAndCancelling() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        #expect(sut.selectionMode == .browse)

        sut.selectHitPoints(fixture.goblin)

        #expect(sut.selectionMode == .value(.hitPoints, combatantName: "Goblin"))
        #expect(sut.pendingValueSelection == .combatant(combatantId: fixture.goblin.id, kind: .hitPoints))
        #expect(sut.activeSelectionModel === sut.selectedValue)
        #expect(sut.selectedValue.onlyChildrenFrom == fixture.goblin.sourceCharacterId)
#if os(macOS)
        #expect(sut.isInspectorPresented)
        #expect(sut.selectionPresentation == nil)
#else
        #expect(sut.selectionPresentation?.id == fixture.goblin.id)
#endif

        sut.cancelSelection()

        #expect(sut.selectionMode == .browse)
        #expect(sut.pendingValueSelection == nil)
        #expect(sut.selectedValue.onlyChildrenFrom == nil)
        #expect(sut.activeSelectionModel === sut.selectedCharacter)
    }

    @Test("Closing the inspector ends a pending choice")
    func closingTheInspectorEndsThePendingChoice() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        sut.selectInitiative(fixture.goblin)
        sut.isInspectorPresented = true
        #expect(sut.selectionMode == .value(.initiative, combatantName: "Goblin"))

        sut.isInspectorPresented = false

        // Reopened, it shows every Character again, not the goblin's values.
        #expect(sut.selectionMode == .browse)
        #expect(sut.selectedValue.onlyChildrenFrom == nil)
    }

    @Test("A token without a Character is asked for one instead of a value")
    func choosingAValueWithoutACharacterAsksForOne() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel

        sut.selectHitPoints(fixture.blank)

        #expect(sut.selectionMode == .character(combatantName: "Blank"))
        #expect(sut.pendingCharacterCombatantId == fixture.blank.id)
        #expect(sut.pendingValueSelection == nil)
    }

    @Test("Choosing a settings pattern is its own mode")
    func choosingASettingsPattern() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel

        sut.selectConfiguredValue(.initiative)

        #expect(sut.selectionMode == .pattern(.initiative))
        #expect(sut.selectedValue.onlyChildrenFrom == nil)
    }

    @Test("Dropping a Character on a token ends the pending choice for it")
    func droppingACharacterEndsThePendingChoice() async throws {
        // Given: "Choose a Character" is pending for the blank token.
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        sut.chooseCharacter(for: fixture.blank)
        #expect(sut.pendingCharacterCombatantId == fixture.blank.id)

        // When: the Character is dragged onto the token instead of clicked.
        let dropped = LinkCharacterData(itemId: fixture.spareCharacterId, name: "Orc")
        #expect(sut.assignDroppedCharacter(dropped, to: fixture.blank.id, controller: fixture.controller))

        // Then: assigned, and the list is not left waiting for a pick.
        #expect(fixture.controller.model.combatant(id: fixture.blank.id)?.sourceCharacterId == fixture.spareCharacterId)
        #expect(sut.pendingCharacterCombatantId == nil)
        #expect(sut.selectionMode == .browse)
        #expect(sut.selectionPresentation == nil)
    }

    @Test("A drop that assigns nothing keeps the pending choice")
    func failedDropKeepsThePendingChoice() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        sut.selectHitPoints(fixture.goblin)

        // A value of a Character that is not the goblin's.
        let foreign = LinkCharacterData(itemId: UUID(), entryId: UUID(), name: "HP")
        #expect(!sut.assignDroppedValue(foreign, to: fixture.goblin.id, kind: .hitPoints, controller: fixture.controller))
        // A Character row without an entry is no value at all.
        let noEntry = LinkCharacterData(itemId: UUID(), name: "Orc")
        #expect(!sut.assignDroppedValue(noEntry, to: fixture.goblin.id, kind: .hitPoints, controller: fixture.controller))

        #expect(sut.selectionMode == .value(.hitPoints, combatantName: "Goblin"))
    }

    // MARK: - Battle lifecycle

    @Test("Only a battle that just ended closes the screen, and it drops every pending flow")
    func battleEndClosesTheScreen() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        sut.selectHitPoints(fixture.goblin)
        sut.requestEnd()
        #expect(sut.isEndConfirmationPresented)

        #expect(!sut.battleRunningDidChange(wasRunning: false, isRunning: true))
        #expect(!sut.battleRunningDidChange(wasRunning: true, isRunning: true))
        #expect(!sut.battleRunningDidChange(wasRunning: false, isRunning: false))
        #expect(sut.selectionMode != .browse)

        #expect(sut.battleRunningDidChange(wasRunning: true, isRunning: false))

        #expect(sut.selectionMode == .browse)
        #expect(sut.selectionPresentation == nil)
        #expect(!sut.isEndConfirmationPresented)
    }

    // MARK: - Turn order

    @Test("A dropped card takes the place of the card it was dropped on")
    func movingACardOntoAnother() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        let model = fixture.controller.model
        let cards = model.entries.map(\.id)
        #expect(cards.count == 3)

        // Last onto first: moves to the top.
        sut.moveCard(cards[2], onto: cards[0], controller: fixture.controller)
        #expect(model.entries.map(\.id) == [cards[2], cards[0], cards[1]])

        // First onto last: moves to the end.
        sut.moveCard(cards[2], onto: cards[1], controller: fixture.controller)
        #expect(model.entries.map(\.id) == [cards[0], cards[1], cards[2]])

        // Onto itself, or an unknown card: nothing moves.
        sut.moveCard(cards[0], onto: cards[0], controller: fixture.controller)
        sut.moveCard(UUID(), onto: cards[0], controller: fixture.controller)
        #expect(model.entries.map(\.id) == cards)
    }

    @Test("The accessibility actions move a card one place and stop at the ends")
    func movingACardByOne() async throws {
        let fixture = try await BattleScreenFixture.make()
        let sut = fixture.screenModel
        let model = fixture.controller.model
        let cards = model.entries.map(\.id)

        sut.moveCard(cards[0], by: 1, controller: fixture.controller)
        #expect(model.entries.map(\.id) == [cards[1], cards[0], cards[2]])

        sut.moveCard(cards[0], by: -1, controller: fixture.controller)
        #expect(model.entries.map(\.id) == cards)

        sut.moveCard(cards[0], by: -1, controller: fixture.controller)
        sut.moveCard(cards[2], by: 1, controller: fixture.controller)
        #expect(model.entries.map(\.id) == cards)
    }

    @Test("The drag payload carries the card id and ignores other text")
    func dragPayload() {
        let id = UUID()

        #expect(BattleEntryDragPayload.entryId(from: BattleEntryDragPayload.string(for: id)) == id)
        #expect(BattleEntryDragPayload.entryId(from: id.uuidString) == nil)
        #expect(BattleEntryDragPayload.entryId(from: "some dragged text") == nil)
    }

    // MARK: - Ownership

    /// `BattleRoundController` holds its root `unowned`, and views keep
    /// copies of it. That is only sound while none of the battle round's
    /// objects keeps the root alive, or outlives it holding a strong path
    /// back to it.
    @Test("The battle round's objects do not keep the game root alive")
    func battleObjectsDoNotRetainTheRoot() async throws {
        var root: GameRoot? = try await MockRoot.createGameRoot()
        weak let weakRoot = root
        let controller = try #require(root).battleRoundController
        let screenModel = BattleRoundScreenModel(model: controller.model)
        let log = try #require(root).battleRoundBroadcastLog

        root = nil

        #expect(weakRoot == nil)
        // The battle objects themselves are still alive here.
        #expect(screenModel.selectionMode == .browse)
        #expect(log.shouldSend(battleRound: BattleRoundNetworkState(
            mapId: UUID(),
            isRunning: false,
            roundCounter: 0,
            activePinId: nil,
            sequence: 0
        )))
    }

    // MARK: - Inspector prompt

#if os(macOS)
    @Test("The inspector says what it is waiting for")
    func inspectorPrompt() {
        #expect(BattleRoundSelectionPrompt(mode: .browse) == nil)
        #expect(BattleRoundSelectionPrompt(mode: .character(combatantName: "Goblin"))?.detail == "Goblin")
        #expect(BattleRoundSelectionPrompt(mode: .value(.hitPoints, combatantName: "Goblin"))?.detail == "Goblin")
        #expect(BattleRoundSelectionPrompt(mode: .pattern(.initiative))?.detail != nil)
    }
#endif
}

// MARK: - Fixture

/// A running battle on the master's device: a hero, a goblin with a
/// Character and a token without one.
@MainActor
struct BattleScreenFixture {
    let root: GameRoot
    let screenModel: BattleRoundScreenModel
    let mapId: UUID
    let goblin: BattleCombatant
    let blank: BattleCombatant
    let spareCharacterId: UUID

    var controller: BattleRoundController { root.battleRoundController }

    static func make() async throws -> BattleScreenFixture {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )

        let heroCharacterId = UUID()
        let goblinCharacterId = UUID()
        let spareCharacterId = UUID()
        for character in [
            ValueModel(id: heroCharacterId, name: "Hero"),
            ValueModel(id: goblinCharacterId, name: "Goblin"),
            ValueModel(id: spareCharacterId, name: "Orc")
        ] {
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
        let goblinPin = MapPinModel(id: UUID(), name: "Goblin", characterId: goblinCharacterId, location: CGPoint(x: 60, y: 60))
        let blankPin = MapPinModel(id: UUID(), name: "Blank", location: CGPoint(x: 80, y: 80))
        let map = MapModel(
            id: UUID(),
            name: "Battle map",
            entries: [room],
            mapPins: [
                MapPinModel(id: UUID(), name: "Hero", characterId: heroCharacterId, location: CGPoint(x: 20, y: 20), isPlayer: true),
                goblinPin,
                blankPin
            ]
        )
        root.mapRoot.gameController.setGame(item: map, itemId: map.id)
        try #require(root.mapRoot.gameController.startBattle(itemId: map.id))

        let model = root.battleRoundController.model
        return BattleScreenFixture(
            root: root,
            screenModel: BattleRoundScreenModel(model: model),
            mapId: map.id,
            goblin: try #require(model.combatant(pinId: goblinPin.id)),
            blank: try #require(model.combatant(pinId: blankPin.id)),
            spareCharacterId: spareCharacterId
        )
    }
}
