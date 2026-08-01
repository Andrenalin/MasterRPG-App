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

    private func square(x: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: x, y: 0),
            CGPoint(x: x + 100, y: 0),
            CGPoint(x: x + 100, y: 100),
            CGPoint(x: x, y: 100)
        ]
    }
}
