// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG

/// Covers `resolveBattleConfiguredValues`'s name-pattern scan
/// (`GameController.gameEntry(matchingAny:characterId:)`), which
/// `BattleRoundController.assignCharacter` triggers whenever a monster pin
/// with no prior Character gets one assigned mid-battle.
@MainActor
@Suite("Battle round configured value scanning")
struct BattleRoundConfiguredValueScanningTests {
    @Test("Assigning a Character to an empty monster pin resolves both ini and HP entry ids by direct name match")
    func directNameMatchResolvesBothEntryIds() async throws {
        let root = try await MockRoot.createGameRoot()
        let (sut, combatantId) = try startBattleWithEmptyMonster(root: root)

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Goblin",
                entries: [
                    ValueEntryModel(id: UUID(), name: "Ini", type: .text, value: "15"),
                    ValueEntryModel(id: UUID(), name: "HP", type: .text, value: "20")
                ]
            ),
            isInsert: true
        )

        #expect(root.battleRoundController.assignCharacter(combatantId, characterId))

        let combatant = try #require(sut.battleRoundModel.combatant(id: combatantId))
        let gameCharacterId = try #require(combatant.gameCharacterId)
        #expect(combatant.initiative == 15)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.initiativeEntryId)
            ) == "15"
        )
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.hitPointsEntryId)
            ) == "20"
        )
    }

    @Test("Ini and HP are resolved via an embedded link even when the entry's own name doesn't match")
    func linkedNameMatchResolvesBothEntryIds() async throws {
        let root = try await MockRoot.createGameRoot()
        let (sut, combatantId) = try startBattleWithEmptyMonster(root: root)

        // Neither entry's own name is "Ini"/"HP" — only a markdown link
        // embedded in its value is display-named that way, e.g. an entry
        // named "Initiative Bonus" that links to a "Ini" reference entry.
        let iniValue = "[Ini](RPG://VALUES/0/\(UUID().uuidString)/\(UUID().uuidString))"
        let hpValue = "[HP](RPG://VALUES/0/\(UUID().uuidString)/\(UUID().uuidString))"
        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Skeleton",
                entries: [
                    ValueEntryModel(id: UUID(), name: "Initiative Bonus", type: .text, value: iniValue),
                    ValueEntryModel(id: UUID(), name: "Hit Points Total", type: .text, value: hpValue)
                ]
            ),
            isInsert: true
        )

        #expect(root.battleRoundController.assignCharacter(combatantId, characterId))

        let combatant = try #require(sut.battleRoundModel.combatant(id: combatantId))
        let gameCharacterId = try #require(combatant.gameCharacterId)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.initiativeEntryId)
            ) == iniValue
        )
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.hitPointsEntryId)
            ) == hpValue
        )
    }

    @Test("Ini and HP are resolved when nested inside a value group table")
    func nestedContentMatchResolvesBothEntryIds() async throws {
        let root = try await MockRoot.createGameRoot()
        let (sut, combatantId) = try startBattleWithEmptyMonster(root: root)

        // "Ini"/"HP" don't live on the Character's own top-level entries —
        // only inside a nested value "group" table reached via `valueId`.
        let groupId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: groupId,
                name: "Combat Stats",
                entries: [
                    ValueEntryModel(id: UUID(), name: "Ini", type: .text, value: "9"),
                    ValueEntryModel(id: UUID(), name: "HP", type: .text, value: "40")
                ]
            ),
            isInsert: true
        )
        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Cultist",
                entries: [
                    ValueEntryModel(id: UUID(), name: "Stats", type: .text, value: "", valueId: groupId)
                ]
            ),
            isInsert: true
        )

        #expect(root.battleRoundController.assignCharacter(combatantId, characterId))

        let combatant = try #require(sut.battleRoundModel.combatant(id: combatantId))
        let gameCharacterId = try #require(combatant.gameCharacterId)
        #expect(combatant.initiative == 9)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.initiativeEntryId)
            ) == "9"
        )
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: gameCharacterId,
                entryId: try #require(combatant.hitPointsEntryId)
            ) == "40"
        )
    }

    /// Starts a battle on a fresh map with a single non-player pin that
    /// carries no `characterId`, mirroring a monster token dropped before
    /// its stat block is chosen.
    private func startBattleWithEmptyMonster(
        root: GameRoot
    ) throws -> (sut: MapRPG.GameController, combatantId: UUID) {
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )

        let sut = root.mapRoot.gameController
        sut.battleRoundSettings.initiativeNames = ["Ini"]
        sut.battleRoundSettings.hitPointsNames = ["HP"]

        let mapId = UUID()
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: square(x: 0),
            focused: true
        )
        let monsterPin = MapPinModel(id: UUID(), name: "Goblin one", location: CGPoint(x: 30, y: 30))
        let map = MapModel(id: mapId, name: "Dungeon", entries: [room], mapPins: [monsterPin])
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))
        let combatant = try #require(sut.battleRoundModel.combatant(pinId: monsterPin.id))
        #expect(combatant.gameCharacterId == nil)
        return (sut, combatant.id)
    }

    @Test("Assigning a Character with an HP entry computes and persists pin.healthPercent")
    func assigningCharacterComputesHealthPercent() async throws {
        let root = try await MockRoot.createGameRoot()
        let (sut, combatantId) = try startBattleWithEmptyMonster(root: root)

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Goblin",
                entries: [
                    ValueEntryModel(id: UUID(), name: "Ini", type: .text, value: "15"),
                    ValueEntryModel(id: UUID(), name: "HP", type: .text, value: "20")
                ]
            ),
            isInsert: true
        )

        #expect(root.battleRoundController.assignCharacter(combatantId, characterId))

        let combatant = try #require(sut.battleRoundModel.combatant(id: combatantId))
        let mapId = try #require(sut.battleRoundModel.mapId)
        let map = try #require(sut.gameModel.itemData[mapId] as? MapModel)
        let pin = try #require(map.mapPins.first { $0.id == combatant.pinId })

        #expect(sut.healthPercent(for: combatant) == 100)
        #expect(pin.healthPercent == 100)
    }

    @Test("A player pin already linked to a Character before battle start gets pin.healthPercent computed")
    func playerPinLinkedBeforeStartComputesHealthPercent() async throws {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let sut = root.mapRoot.gameController
        sut.battleRoundSettings.hitPointsNames = ["HP"]

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Hero",
                entries: [ValueEntryModel(id: UUID(), name: "HP", type: .number, value: "40|-10")]
            ),
            isInsert: true
        )

        let playerId = UUID()
        let playerPin = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 10, y: 10),
            isPlayer: true,
            players: [playerId]
        )
        var linkedPin = playerPin
        linkedPin.characterId = characterId
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [linkedPin])
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))

        let combatant = try #require(sut.battleRoundModel.combatant(pinId: playerId))
        #expect(combatant.gameCharacterId == characterId)
        #expect(combatant.hitPointsEntryId != nil)

        let liveMap = try #require(sut.gameModel.itemData[mapId] as? MapModel)
        let pin = try #require(liveMap.mapPins.first { $0.id == playerId })
        #expect(sut.healthPercent(for: combatant) == 75)
        #expect(pin.healthPercent == 75)
    }

    /// `.text` is an easy, reasonable choice for a hit-points entry — a game
    /// master just typing a number has no reason to know the "type" picker
    /// matters here. `LinkController.calculate(entry:)` only evaluates the
    /// "base|modifier" convention for `.number`/`.decimal` entries though
    /// (`ValueEntryModel.canCalculate`), which silently left `healthPercent`
    /// `nil` forever for a `.text` entry before `GameController.healthPercent(for:)`
    /// grew its own fallback evaluation.
    @Test("A .text-typed hit-points entry still computes pin.healthPercent")
    func textTypedHitPointsEntryComputesHealthPercent() async throws {
        let root = try await MockRoot.createGameRoot()
        let (sut, combatantId) = try startBattleWithEmptyMonster(root: root)

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Goblin",
                entries: [ValueEntryModel(id: UUID(), name: "HP", type: .text, value: "40|-10")]
            ),
            isInsert: true
        )

        #expect(root.battleRoundController.assignCharacter(combatantId, characterId))

        let combatant = try #require(sut.battleRoundModel.combatant(id: combatantId))
        let mapId = try #require(sut.battleRoundModel.mapId)
        let map = try #require(sut.gameModel.itemData[mapId] as? MapModel)
        let pin = try #require(map.mapPins.first { $0.id == combatant.pinId })

        #expect(sut.healthPercent(for: combatant) == 75)
        #expect(pin.healthPercent == 75)
    }

    @Test("A monster pin already linked to a Character before battle start gets pin.healthPercent computed")
    func monsterPinLinkedBeforeStartComputesHealthPercent() async throws {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let sut = root.mapRoot.gameController
        sut.battleRoundSettings.hitPointsNames = ["HP"]

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Goblin",
                entries: [ValueEntryModel(id: UUID(), name: "HP", type: .text, value: "20")]
            ),
            isInsert: true
        )

        var monsterPin = MapPinModel(id: UUID(), name: "Goblin one", location: CGPoint(x: 30, y: 30))
        monsterPin.characterId = characterId
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: square(x: 0),
            focused: true
        )
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon", entries: [room], mapPins: [monsterPin])
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))

        let combatant = try #require(sut.battleRoundModel.combatant(pinId: monsterPin.id))
        #expect(combatant.gameCharacterId != nil)
        #expect(combatant.hitPointsEntryId != nil)

        let liveMap = try #require(sut.gameModel.itemData[mapId] as? MapModel)
        let pin = try #require(liveMap.mapPins.first { $0.id == monsterPin.id })
        #expect(sut.healthPercent(for: combatant) == 100)
        #expect(pin.healthPercent == 100)
    }

    /// Goes through the real production entry points — `BattleRoundController.start()`
    /// and `.nextRound()` (GameRPG layer), not the lower-level `MapRPG.GameController`
    /// calls the other tests use directly — and checks `pin.healthPercent` on the exact
    /// `MapModel` instance `MapPinView`/`GameTableModel` read pins from
    /// (`root.mapRoot.gameController.gameItem(for:)`), both right after battle start and
    /// again after a round advance, to confirm it's actually saved where rendering reads it
    /// and isn't reset by the turn/round broadcast.
    @Test("BattleRoundController.start() and .nextRound() save pin.healthPercent where the map reads it")
    func battleRoundControllerSavesHealthPercentWhereMapReadsIt() async throws {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        root.gameModel.masterController = MasterController(root: root, asProxy: false)
        root.mapRoot.gameController.battleRoundSettings.hitPointsNames = ["HP"]

        let characterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(
                id: characterId,
                name: "Hero",
                entries: [ValueEntryModel(id: UUID(), name: "HP", type: .number, value: "40|-10")]
            ),
            isInsert: true
        )

        let playerId = UUID()
        var linkedPin = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 10, y: 10),
            isPlayer: true,
            players: [playerId]
        )
        linkedPin.characterId = characterId
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [linkedPin])
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        root.mapRoot.gameController.setGame(item: map.copy(), itemId: mapId)

        #expect(root.battleRoundController.start())

        let mapAfterStart = root.mapRoot.gameController.gameItem(for: mapId)
        let pinAfterStart = try #require(mapAfterStart.mapPins.first { $0.id == playerId })
        #expect(pinAfterStart.healthPercent == 75)

        #expect(root.battleRoundController.nextRound())

        let mapAfterRound = root.mapRoot.gameController.gameItem(for: mapId)
        #expect(mapAfterRound === mapAfterStart)
        let pinAfterRound = try #require(mapAfterRound.mapPins.first { $0.id == playerId })
        #expect(pinAfterRound.healthPercent == 75)
    }

    /// Reproduces the real-world case reported against this feature: the
    /// hit-points entry's own value isn't a literal number at all, it's a
    /// markdown link to a *separate* entry — possibly on a different table —
    /// whose own value is itself a further-linked formula. `healthPercent(for:)`
    /// used to parse the raw, un-resolved text before "|" directly as the
    /// "base", which fails outright for a link; it now resolves both the
    /// base and the full "base|modifier" expression through the same
    /// link-substitution engine the entry's own display value uses. Uses a
    /// player pin so `gameCharacterId` is the Character's own id directly
    /// (no battle-copy duplication in the way), isolating link resolution.
    @Test("A hit-points entry that's a link to a further-linked formula still computes pin.healthPercent")
    func linkedFormulaHitPointsEntryComputesHealthPercent() async throws {
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let sut = root.mapRoot.gameController
        sut.battleRoundSettings.hitPointsNames = ["Aktuelle"]

        // "KÖR+HÄ+10+LK Level+3" pattern from the bug report: a formula entry
        // linking to two further stat entries on the same stats table.
        let statsId = UUID()
        let körEntry = ValueEntryModel(id: UUID(), name: "KÖR", type: .number, value: "12")
        let häEntry = ValueEntryModel(id: UUID(), name: "HÄ", type: .number, value: "8")
        let statsModel = ValueModel(id: statsId, name: "Stats", entries: [körEntry, häEntry])
        root.characterRoot.itemController.replace(model: statsModel, isInsert: true)

        let formulaValue = "\(statsModel.url(linkNumber: 0, entryId: körEntry.id))+\(statsModel.url(linkNumber: 0, entryId: häEntry.id))+10"
        let lebenskraftEntry = ValueEntryModel(id: UUID(), name: "Lebenskraft", type: .number, value: formulaValue)

        let characterId = UUID()
        let characterModel = ValueModel(id: characterId, name: "Hero", entries: [lebenskraftEntry])

        // "Aktuelle" links to "Lebenskraft" with a "|-10" modifier — mirrors
        // an entry edited to record 10 points of damage against the linked
        // max-HP formula.
        let aktuelleValue = "\(characterModel.url(linkNumber: 0, entryId: lebenskraftEntry.id))|-10"
        let aktuelleEntry = ValueEntryModel(id: UUID(), name: "Aktuelle", type: .number, value: aktuelleValue)
        var fullCharacterModel = characterModel
        fullCharacterModel.entries.append(aktuelleEntry)
        root.characterRoot.itemController.replace(model: fullCharacterModel, isInsert: true)

        let playerId = UUID()
        var playerPin = MapPinModel(
            id: playerId,
            name: "Hero",
            location: CGPoint(x: 10, y: 10),
            isPlayer: true,
            players: [playerId]
        )
        playerPin.characterId = characterId
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Dungeon", mapPins: [playerPin])
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))

        let combatant = try #require(sut.battleRoundModel.combatant(pinId: playerId))
        #expect(combatant.gameCharacterId == characterId)
        #expect(combatant.hitPointsEntryId == aktuelleEntry.id)

        // KÖR (12) + HÄ (8) + 10 = 30 max, minus 10 damage = 20 current → 66.67%.
        let percent = try #require(sut.healthPercent(for: combatant))
        #expect(abs(percent - (20.0 / 30.0 * 100)) < 0.01)

        let liveMap = try #require(sut.gameModel.itemData[mapId] as? MapModel)
        let pin = try #require(liveMap.mapPins.first { $0.id == playerId })
        #expect(pin.healthPercent != nil)
        #expect(abs((pin.healthPercent ?? 0) - (20.0 / 30.0 * 100)) < 0.01)
    }

    private func square(x: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: x, y: 0),
            CGPoint(x: x + 100, y: 0),
            CGPoint(x: x + 100, y: 100),
            CGPoint(x: x, y: 100)
        ]
    }
}
