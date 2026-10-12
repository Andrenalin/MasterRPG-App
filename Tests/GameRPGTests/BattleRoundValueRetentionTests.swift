// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Battle round value retention")
struct BattleRoundValueRetentionTests {
    @Test("Explicit player values and character-derived monster values persist across battles for reused pins")
    func retainsValuesAcrossBattles() async throws {
        // Given
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let sut = root.mapRoot.gameController
        sut.battleRoundSettings.initiativeNames = ["Ini"]
        sut.battleRoundSettings.hitPointsNames = ["HP"]

        let player1CharacterId = UUID()
        let player2CharacterId = UUID()
        let player3CharacterId = UUID()
        let monster1TemplateId = UUID()
        let monster2TemplateId = UUID()
        let monster3TemplateId = UUID()

        func character(_ id: UUID, name: String, iniAndHP: (String, String)? = nil, speedAndVitality: (String, String)? = nil) -> ValueModel {
            var entries: [ValueEntryModel] = []
            if let (ini, hp) = iniAndHP {
                entries.append(ValueEntryModel(id: UUID(), name: "Ini", type: .text, value: ini))
                entries.append(ValueEntryModel(id: UUID(), name: "HP", type: .text, value: hp))
            }
            if let (speed, vitality) = speedAndVitality {
                entries.append(ValueEntryModel(id: UUID(), name: "Speed", type: .text, value: speed))
                entries.append(ValueEntryModel(id: UUID(), name: "Vitality", type: .text, value: vitality))
            }
            return ValueModel(id: id, name: name, entries: entries)
        }

        // Players carry their initiative/HP on entries named differently
        // from the default "Ini"/"HP" pattern, so they can only be resolved
        // by explicitly assigning the entry (assignValueEntry), never by
        // the automatic name-based detection monsters rely on.
        root.characterRoot.itemController.replace(
            model: character(player1CharacterId, name: "Aria", speedAndVitality: ("14", "22")),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: character(player2CharacterId, name: "Borin", speedAndVitality: ("9", "31")),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: character(player3CharacterId, name: "Cassia", speedAndVitality: ("12", "19")),
            isInsert: true
        )
        // Monster templates use the default "Ini"/"HP" names, so once a
        // Character is assigned to their (initially empty) token, the
        // battle auto-detects their values with no explicit assignment.
        root.characterRoot.itemController.replace(
            model: character(monster1TemplateId, name: "Goblin", iniAndHP: ("18", "30")),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: character(monster2TemplateId, name: "Skeleton", iniAndHP: ("11", "15")),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: character(monster3TemplateId, name: "Cultist", iniAndHP: ("7", "12")),
            isInsert: true
        )

        let mapId = UUID()
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: square(x: 0),
            focused: true
        )
        let player1Pin = MapPinModel(
            id: UUID(), name: "Aria", characterId: player1CharacterId,
            location: CGPoint(x: 10, y: 10), isPlayer: true
        )
        let player2Pin = MapPinModel(
            id: UUID(), name: "Borin", characterId: player2CharacterId,
            location: CGPoint(x: 20, y: 20), isPlayer: true
        )
        let monster1Pin = MapPinModel(id: UUID(), name: "Goblin one", location: CGPoint(x: 30, y: 30))
        let monster2Pin = MapPinModel(id: UUID(), name: "Skeleton", location: CGPoint(x: 40, y: 40))
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room],
            mapPins: [player1Pin, player2Pin, monster1Pin, monster2Pin]
        )
        root.mapRoot.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        // When: battle one starts with both monster tokens still empty.
        #expect(sut.startBattle(itemId: mapId))
        let battleModel = sut.battleRoundModel

        let player1Combatant = try #require(battleModel.combatant(pinId: player1Pin.id))
        let player2Combatant = try #require(battleModel.combatant(pinId: player2Pin.id))
        let monster1Combatant = try #require(battleModel.combatant(pinId: monster1Pin.id))
        let monster2Combatant = try #require(battleModel.combatant(pinId: monster2Pin.id))
        #expect(monster1Combatant.gameCharacterId == nil)
        #expect(monster2Combatant.gameCharacterId == nil)

        // When: characterId is sent for both monsters — the auto-detected
        // "Ini"/"HP" entries from their template should immediately apply.
        #expect(sut.assignBattleCharacter(
            itemId: mapId, combatantId: monster1Combatant.id, characterId: monster1TemplateId
        ))
        #expect(sut.assignBattleCharacter(
            itemId: mapId, combatantId: monster2Combatant.id, characterId: monster2TemplateId
        ))

        // Then: monster ini/HP came from the character data via the default
        // name pattern, with no explicit entry assignment.
        let resolvedMonster1 = try #require(battleModel.combatant(id: monster1Combatant.id))
        let monster1GameId = try #require(resolvedMonster1.gameCharacterId)
        #expect(resolvedMonster1.initiative == 18)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: monster1GameId,
                entryId: try #require(resolvedMonster1.hitPointsEntryId)
            ) == "30"
        )
        let resolvedMonster2 = try #require(battleModel.combatant(id: monster2Combatant.id))
        let monster2GameId = try #require(resolvedMonster2.gameCharacterId)
        #expect(resolvedMonster2.initiative == 11)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: monster2GameId,
                entryId: try #require(resolvedMonster2.hitPointsEntryId)
            ) == "15"
        )

        // When: players get their ini/HP from an explicitly chosen entry —
        // never named "Ini"/"HP", so the default pattern could never have
        // found them on its own.
        func speedEntryId(for characterId: UUID) throws -> UUID {
            try #require(
                root.characterRoot.itemController.itemSync(for: characterId)?
                    .entries.first { $0.name == "Speed" }?.id
            )
        }
        func vitalityEntryId(for characterId: UUID) throws -> UUID {
            try #require(
                root.characterRoot.itemController.itemSync(for: characterId)?
                    .entries.first { $0.name == "Vitality" }?.id
            )
        }

        #expect(root.battleRoundController.assignValueEntry(
            combatantId: player1Combatant.id,
            sourceCharacterId: player1CharacterId,
            sourceEntryId: try speedEntryId(for: player1CharacterId),
            kind: .initiative
        ))
        #expect(root.battleRoundController.assignValueEntry(
            combatantId: player1Combatant.id,
            sourceCharacterId: player1CharacterId,
            sourceEntryId: try vitalityEntryId(for: player1CharacterId),
            kind: .hitPoints
        ))
        #expect(root.battleRoundController.assignValueEntry(
            combatantId: player2Combatant.id,
            sourceCharacterId: player2CharacterId,
            sourceEntryId: try speedEntryId(for: player2CharacterId),
            kind: .initiative
        ))
        #expect(root.battleRoundController.assignValueEntry(
            combatantId: player2Combatant.id,
            sourceCharacterId: player2CharacterId,
            sourceEntryId: try vitalityEntryId(for: player2CharacterId),
            kind: .hitPoints
        ))

        // Then
        let resolvedPlayer1 = try #require(battleModel.combatant(id: player1Combatant.id))
        #expect(resolvedPlayer1.initiative == 14)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: player1CharacterId,
                entryId: try #require(resolvedPlayer1.hitPointsEntryId)
            ) == "22"
        )
        let resolvedPlayer2 = try #require(battleModel.combatant(id: player2Combatant.id))
        #expect(resolvedPlayer2.initiative == 9)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: player2CharacterId,
                entryId: try #require(resolvedPlayer2.hitPointsEntryId)
            ) == "31"
        )

        // When: the battle ends, and the roster changes before the next one
        // starts — player 2 leaves, a new player and a new (empty) monster
        // token take their place; player 1 and monster 1 stay on the map.
        #expect(sut.endBattle(itemId: mapId))

        let player3Pin = MapPinModel(
            id: UUID(), name: "Cassia", characterId: player3CharacterId,
            location: CGPoint(x: 50, y: 50), isPlayer: true
        )
        let monster3Pin = MapPinModel(id: UUID(), name: "Cultist", location: CGPoint(x: 60, y: 60))
        let liveMap = sut.gameItem(for: mapId)
        liveMap.mapPins.removeAll { $0.id == player2Pin.id || $0.id == monster2Pin.id }
        liveMap.mapPins.append(contentsOf: [player3Pin, monster3Pin])

        // When: battle two starts with the reused pins plus the new roster.
        #expect(sut.startBattle(itemId: mapId))

        // Then: the reused player kept its explicitly-assigned ini/HP.
        let retainedPlayer = try #require(battleModel.combatant(pinId: player1Pin.id))
        #expect(retainedPlayer.sourceCharacterId == player1CharacterId)
        #expect(retainedPlayer.gameCharacterId == player1CharacterId)
        #expect(retainedPlayer.initiative == 14)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: player1CharacterId,
                entryId: try #require(retainedPlayer.hitPointsEntryId)
            ) == "22"
        )

        // Then: the reused monster's pin still references its battle copy
        // from the previous encounter (so `sourceCharacterId` now reads as
        // that copy's id too, since `makeBattleCombatant` always takes the
        // pin's *current* characterId), and re-detection against that same
        // (unchanged) copy yields the same ini/HP as before.
        let retainedMonster = try #require(battleModel.combatant(pinId: monster1Pin.id))
        #expect(retainedMonster.sourceCharacterId == monster1GameId)
        #expect(retainedMonster.gameCharacterId == monster1GameId)
        #expect(retainedMonster.initiative == 18)
        #expect(
            root.characterRoot.valueGameControllable.gameEntryDisplayValue(
                characterId: monster1GameId,
                entryId: try #require(retainedMonster.hitPointsEntryId)
            ) == "30"
        )
        #expect(liveMap[MapPinId.id, monster1Pin.id].characterId == monster1GameId)

        // Then: the new player and new (still empty) monster token are
        // present but carry none of the previous encounter's state.
        let newPlayerCombatant = try #require(battleModel.combatant(pinId: player3Pin.id))
        #expect(newPlayerCombatant.sourceCharacterId == player3CharacterId)
        #expect(newPlayerCombatant.initiative == nil)
        let newMonsterCombatant = try #require(battleModel.combatant(pinId: monster3Pin.id))
        #expect(newMonsterCombatant.gameCharacterId == nil)
        #expect(newMonsterCombatant.initiative == nil)

        // And the departed player/monster from battle one are gone.
        #expect(battleModel.combatant(pinId: player2Pin.id) == nil)
        #expect(battleModel.combatant(pinId: monster2Pin.id) == nil)
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
