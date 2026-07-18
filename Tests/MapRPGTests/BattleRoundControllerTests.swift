// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import MapRPG

@MainActor
@Suite("Battle round map controller")
struct BattleRoundControllerTests {
    @Test("Battle seeds players and only the last activated room pins using independent character copies")
    func seedsLastRoomAndCopiesCharacters() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let playerCharacterId = UUID()
        let monsterCharacterId = UUID()
        let outsideCharacterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: playerCharacterId, name: "Hero", description: "Player stats"),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(id: monsterCharacterId, name: "Goblin", description: "Monster stats"),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(id: outsideCharacterId, name: "Dragon"),
            isInsert: true
        )

        let room = MapEntryModel(
            id: UUID(),
            name: "Activated Room",
            content: "",
            coordinates: square(x: 0)
        )
        let otherRoom = MapEntryModel(
            id: UUID(),
            name: "Other Room",
            content: "",
            coordinates: square(x: 200)
        )
        let playerPin = MapPinModel(
            id: UUID(),
            name: "Hero",
            characterId: playerCharacterId,
            location: CGPoint(x: 250, y: 50),
            isPlayer: true
        )
        let roomMonster = MapPinModel(
            id: UUID(),
            name: "Goblin",
            characterId: monsterCharacterId,
            location: CGPoint(x: 50, y: 50)
        )
        let outsideMonster = MapPinModel(
            id: UUID(),
            name: "Dragon",
            characterId: outsideCharacterId,
            location: CGPoint(x: 250, y: 50)
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room, otherRoom],
            mapPins: [playerPin, roomMonster, outsideMonster]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        #expect(sut.toggleRoomFocus(itemId: mapId, roomId: room.id))

        // When
        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))

        // Then
        let model = sut.battleRoundModel
        #expect(model.roundCounter == 0)
        #expect(Set(model.combatants.map(\.pinId)) == Set([playerPin.id, roomMonster.id]))
        #expect(model.combatant(pinId: outsideMonster.id) == nil)
        for combatant in model.combatants {
            let sourceId = try #require(combatant.sourceCharacterId)
            let gameId = try #require(combatant.gameCharacterId)
            #expect(gameId != sourceId)
            let copiedCharacter = try #require(
                root.characterRoot.valueGameControllable.battleCharacterCopy(for: gameId)
            )
            #expect(copiedCharacter.id == gameId)
            #expect(copiedCharacter.name == combatant.name)
        }
    }

    @Test("Active attacker is authoritative and highlights synchronize defenders, death, and network state")
    func synchronizesActiveBattleState() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let playerCharacterId = UUID()
        let monsterCharacterId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: playerCharacterId, name: "Hero"),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(id: monsterCharacterId, name: "Goblin"),
            isInsert: true
        )
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: square(x: 0),
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
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room],
            mapPins: [playerPin, monsterPin]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))
        let player = try #require(sut.battleRoundModel.combatant(pinId: playerPin.id))
        let monster = try #require(sut.battleRoundModel.combatant(pinId: monsterPin.id))

        // When
        #expect(sut.activateBattleAttacker(itemId: mapId, combatantId: player.id))
        #expect(sut.toggleHighlightPin(itemId: mapId, pinId: monsterPin.id))

        // Then
        var activeEntry = try #require(sut.battleRoundModel.activeEntry)
        #expect(activeEntry.defenderIds == [monster.id])
        #expect(sut.gameItem(for: mapId)[MapPinId.id, playerPin.id].isHighlighted)
        #expect(sut.selectBattleRollRecipient(itemId: mapId, combatantId: monster.id))
        #expect(sut.battleRoundModel.rollRecipientCombatantId == monster.id)
        #expect(sut.addBattleRoll(
            itemId: mapId,
            combatantId: monster.id,
            total: 12,
            expression: "d20"
        ))
        #expect(sut.setBattleCombatantDead(
            itemId: mapId,
            combatantId: monster.id,
            isDead: true
        ))
        #expect(sut.gameItem(for: mapId)[MapPinId.id, monsterPin.id].isDead)

        // When: dehighlight removes the defender and repairs the roll target.
        #expect(sut.toggleHighlightPin(itemId: mapId, pinId: monsterPin.id))

        // Then
        activeEntry = try #require(sut.battleRoundModel.activeEntry)
        #expect(activeEntry.defenderIds.isEmpty)
        #expect(sut.battleRoundModel.rollRecipientCombatantId == player.id)

        let update = try #require(sut.networkBattleRoundUpdate(for: mapId))
        let state = try #require(BattleRoundNetworkState.decodeData(update.data))
        #expect(state.isRunning)
        #expect(state.roundCounter == 0)
        #expect(state.activePinId == playerPin.id)

        // When / Then
        #expect(sut.endBattle(itemId: mapId))
        #expect(sut.gameItem(for: mapId).mapPins.allSatisfy { !$0.isHighlighted })
        let ended = try #require(sut.networkBattleRoundUpdate(for: mapId))
        #expect(BattleRoundNetworkState.decodeData(ended.data)?.isRunning == false)
    }

    @Test("Repeated battles retain the player copy and replace distinct monster copies")
    func cleansUpAndRefreshesRuntimeCharacters() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let playerCharacterId = UUID()
        let monsterTemplateId = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: playerCharacterId, name: "Hero"),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(id: monsterTemplateId, name: "Goblin template"),
            isInsert: true
        )
        #expect(await root.characterRoot.gameController.setCurrent(
            itemId: playerCharacterId
        ))
        let initialCharacterItems = root.characterRoot.gameController.gameModel.items
        let initialCharacterId = root.characterRoot.gameController.gameModel.currentItemId
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: square(x: 0),
            focused: true
        )
        let playerPin = MapPinModel(
            id: UUID(),
            name: "Hero",
            characterId: playerCharacterId,
            location: CGPoint(x: 10, y: 10),
            isPlayer: true
        )
        let firstMonsterPin = MapPinModel(
            id: UUID(),
            name: "Goblin one",
            characterId: monsterTemplateId,
            location: CGPoint(x: 30, y: 30)
        )
        let secondMonsterPin = MapPinModel(
            id: UUID(),
            name: "Goblin two",
            characterId: monsterTemplateId,
            location: CGPoint(x: 60, y: 60)
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: [room],
            mapPins: [playerPin, firstMonsterPin, secondMonsterPin]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        // When: two pins reuse one monster template in the first battle.
        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))
        let firstPlayer = try #require(sut.battleRoundModel.combatant(pinId: playerPin.id))
        let firstPlayerRuntimeId = try #require(firstPlayer.gameCharacterId)
        #expect(sut.setBattleInitiative(
            itemId: mapId,
            combatantId: firstPlayer.id,
            value: 17
        ))
        let firstMonsterRuntimeIds = Set(
            sut.battleRoundModel.combatants
                .filter { !$0.isPlayer }
                .compactMap(\.gameCharacterId)
        )

        // Then: each monster is independent even though the source is shared.
        #expect(firstMonsterRuntimeIds.count == 2)
        #expect(!firstMonsterRuntimeIds.contains(monsterTemplateId))
        #expect(root.characterRoot.gameController.gameModel.items == initialCharacterItems)
        #expect(root.characterRoot.gameController.gameModel.currentItemId == initialCharacterId)
        #expect(firstMonsterRuntimeIds.allSatisfy {
            root.characterRoot.valueGameControllable.battleCharacterCopy(for: $0) != nil
        })

        // When: ending and reopening the encounter rebuilds monsters.
        #expect(sut.endBattle(itemId: mapId))

        // Then: player state remains available, while old monster copies are released.
        #expect(
            root.characterRoot.valueGameControllable.battleCharacterCopy(
                for: firstPlayerRuntimeId
            ) != nil
        )
        #expect(firstMonsterRuntimeIds.allSatisfy {
            root.characterRoot.valueGameControllable.battleCharacterCopy(for: $0) == nil
        })

        // When
        #expect(sut.startBattle(itemId: mapId, initiativeOrder: .descending))

        // Then
        let retainedPlayer = try #require(
            sut.battleRoundModel.combatant(pinId: playerPin.id)
        )
        #expect(retainedPlayer.gameCharacterId == firstPlayerRuntimeId)
        #expect(retainedPlayer.initiative == 17)
        let secondMonsterRuntimeIds = Set(
            sut.battleRoundModel.combatants
                .filter { !$0.isPlayer }
                .compactMap(\.gameCharacterId)
        )
        #expect(secondMonsterRuntimeIds.count == 2)
        #expect(secondMonsterRuntimeIds.isDisjoint(with: firstMonsterRuntimeIds))
        #expect(root.characterRoot.gameController.gameModel.items == initialCharacterItems)
        #expect(root.characterRoot.gameController.gameModel.currentItemId == initialCharacterId)

        // When: the game session resets rather than merely closing a battle.
        sut.resetBattleRound()

        // Then: the retained player copy and current monster copies are all
        // released, without disturbing the presented Character order.
        #expect(
            root.characterRoot.valueGameControllable.battleCharacterCopy(
                for: firstPlayerRuntimeId
            ) == nil
        )
        #expect(secondMonsterRuntimeIds.allSatisfy {
            root.characterRoot.valueGameControllable.battleCharacterCopy(for: $0) == nil
        })
        #expect(root.characterRoot.gameController.gameModel.items == initialCharacterItems)
        #expect(root.characterRoot.gameController.gameModel.currentItemId == initialCharacterId)
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
