// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import Testing

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Battle round dice attribution")
struct BattleRoundDiceAttributionTests {
    @Test("Character dice results appear below the matching battle photo")
    func characterDiceMatchesPlayerAndNonPlayerRows() async throws {
        // Given
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        let playerId = UUID()
        let playerCharacterId = UUID()
        let monsterCharacterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )

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
            id: playerId,
            name: "Player",
            characterId: playerCharacterId,
            location: CGPoint(x: 20, y: 20),
            isPlayer: true,
            players: [playerId]
        )
        let monsterPin = MapPinModel(
            id: UUID(),
            name: "Monster",
            characterId: monsterCharacterId,
            location: CGPoint(x: 60, y: 60)
        )
        let map = MapModel(
            id: UUID(),
            name: "Battle map",
            entries: [room],
            mapPins: [playerPin, monsterPin]
        )
        root.mapRoot.gameController.setGame(item: map, itemId: map.id)
        #expect(root.mapRoot.gameController.startBattle(
            itemId: map.id,
            initiativeOrder: .descending
        ))

        let battle = root.battleRoundModel
        let player = try #require(battle.combatant(pinId: playerPin.id))
        let monster = try #require(battle.combatant(pinId: monsterPin.id))
        let playerRoll = result(characterId: playerCharacterId, total: 17)
        let monsterRoll = result(characterId: monsterCharacterId, total: 11)

        // When
        root.recordBattleDiceResult(playerRoll, senderId: playerId, isMaster: false)
        root.recordBattleDiceResult(monsterRoll, senderId: masterId, isMaster: true)

        // Then: Surprise stores each result on that combatant's own row.
        let playerEntry = try #require(battle.entries.first { $0.attackerId == player.id })
        let monsterEntry = try #require(battle.entries.first { $0.attackerId == monster.id })
        #expect(battle.rolls(for: player.id, in: playerEntry).map(\.total) == [17])
        #expect(battle.rolls(for: monster.id, in: monsterEntry).map(\.total) == [11])

        // An unlinked master die uses a manually selected non-player target.
        #expect(root.selectBattleRollRecipient(monster.id))
        root.recordBattleDiceResult(
            result(characterId: nil, total: 8),
            senderId: masterId,
            isMaster: true
        )
        let updatedMonsterEntry = try #require(
            battle.entries.first { $0.attackerId == monster.id }
        )
        #expect(battle.rolls(for: monster.id, in: updatedMonsterEntry).map(\.total) == [11, 8])
    }

    private func result(characterId: UUID?, total: Int) -> DiceResultModel {
        let category = characterId.map {
            ResultCategory(id: $0, module: .value)
        } ?? ResultCategory(id: UUID(), module: .dice)
        let dice = DiceSnapshot(
            id: UUID(),
            name: "D20",
            dice: [],
            resultCategory: category
        )
        return DiceResultModel(
            diceModel: dice,
            result: .rolled,
            values: "d20",
            sum: total,
            checked: false
        )
    }
}
