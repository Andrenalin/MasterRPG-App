// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import CharacterRPG
@testable import MapRPG

/// Which opponents (non-player pins) a battle start adds to the roster:
/// the last opened room, else the first room, else every pin of the map.
/// Player pins are always part of the battle.
@MainActor
@Suite("Battle start opponent selection")
struct BattleRoundStartOpponentsTests {
    @Test("Battle start adds only the pins of the last opened room")
    func usesLastOpenedRoom() async throws {
        // Given
        let fixture = try await Fixture.make()
        let sut = fixture.sut

        // When: room B is opened after room A.
        #expect(sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.roomA.id))
        #expect(sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.roomB.id))
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then
        let pinIds = Set(sut.battleRoundModel.combatants.map(\.pinId))
        #expect(pinIds == Set([fixture.playerPin.id, fixture.roomBMonster.id]))
    }

    @Test("Battle start follows the last opened room even when it is the first room")
    func usesLastOpenedRoomWhenItIsTheFirstRoom() async throws {
        // Given
        let fixture = try await Fixture.make()
        let sut = fixture.sut

        // When: room B is opened first, room A last.
        #expect(sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.roomB.id))
        #expect(sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.roomA.id))
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then
        let pinIds = Set(sut.battleRoundModel.combatants.map(\.pinId))
        #expect(pinIds == Set([fixture.playerPin.id, fixture.roomAMonster.id]))
    }

    @Test("Without an opened room, battle start adds the pins of the first room")
    func fallsBackToFirstRoom() async throws {
        // Given: two rooms, none ever opened.
        let fixture = try await Fixture.make()
        let sut = fixture.sut

        // When
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then
        let pinIds = Set(sut.battleRoundModel.combatants.map(\.pinId))
        #expect(pinIds == Set([fixture.playerPin.id, fixture.roomAMonster.id]))
        #expect(sut.battleRoundModel.combatant(pinId: fixture.roomBMonster.id) == nil)
        #expect(sut.battleRoundModel.combatant(pinId: fixture.looseMonster.id) == nil)
    }

    @Test("Without any room, battle start adds every pin of the map")
    func fallsBackToAllPinsWithoutRooms() async throws {
        // Given: a map without rooms.
        let fixture = try await Fixture.make(withRooms: false)
        let sut = fixture.sut

        // When
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then
        let pinIds = Set(sut.battleRoundModel.combatants.map(\.pinId))
        #expect(
            pinIds == Set([
                fixture.playerPin.id,
                fixture.roomAMonster.id,
                fixture.roomBMonster.id,
                fixture.looseMonster.id
            ])
        )
    }

    @Test("Opponents are copied into game memory while players keep their Character")
    func addedOpponentsGetBattleCopies() async throws {
        // Given
        let fixture = try await Fixture.make()
        let sut = fixture.sut
        #expect(sut.toggleRoom(itemId: fixture.mapId, roomId: fixture.roomA.id))

        // When
        #expect(sut.startBattle(itemId: fixture.mapId))

        // Then
        let model = sut.battleRoundModel
        let player = try #require(model.combatant(pinId: fixture.playerPin.id))
        #expect(player.isPlayer)
        #expect(player.gameCharacterId == fixture.playerCharacterId)

        let opponent = try #require(model.combatant(pinId: fixture.roomAMonster.id))
        #expect(!opponent.isPlayer)
        #expect(opponent.sourceCharacterId == fixture.monsterCharacterId)
        let copyId = try #require(opponent.gameCharacterId)
        #expect(copyId != fixture.monsterCharacterId)
        #expect(model.entries.contains { $0.attackerId == opponent.id })
    }

    @Test("Battle start fails on a map without any pin")
    func emptyMapDoesNotStart() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let mapId = UUID()
        let map = MapModel(id: mapId, name: "Empty", entries: [], mapPins: [])
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)

        // When / Then
        #expect(!sut.startBattle(itemId: mapId))
        #expect(!sut.battleRoundModel.isRunning)
    }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    let sut: MapRPG.GameController
    let mapId: UUID
    let roomA: MapEntryModel
    let roomB: MapEntryModel
    let playerPin: MapPinModel
    let roomAMonster: MapPinModel
    let roomBMonster: MapPinModel
    let looseMonster: MapPinModel
    let playerCharacterId: UUID
    let monsterCharacterId: UUID

    /// Room A holds one monster, room B another, a third monster stands in
    /// no room, and the player pin is outside both rooms.
    static func make(withRooms: Bool = true) async throws -> Fixture {
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

        let roomA = MapEntryModel(
            id: UUID(), name: "Room A", content: "", coordinates: square(x: 0)
        )
        let roomB = MapEntryModel(
            id: UUID(), name: "Room B", content: "", coordinates: square(x: 200)
        )
        let playerPin = MapPinModel(
            id: UUID(),
            name: "Hero",
            characterId: playerCharacterId,
            location: CGPoint(x: 600, y: 50),
            isPlayer: true
        )
        let roomAMonster = MapPinModel(
            id: UUID(),
            name: "Goblin A",
            characterId: monsterCharacterId,
            location: CGPoint(x: 50, y: 50)
        )
        let roomBMonster = MapPinModel(
            id: UUID(),
            name: "Goblin B",
            characterId: monsterCharacterId,
            location: CGPoint(x: 250, y: 50)
        )
        let looseMonster = MapPinModel(
            id: UUID(),
            name: "Goblin Loose",
            characterId: monsterCharacterId,
            location: CGPoint(x: 450, y: 50)
        )
        let map = MapModel(
            id: mapId,
            name: "Dungeon",
            entries: withRooms ? [roomA, roomB] : [],
            mapPins: [playerPin, roomAMonster, roomBMonster, looseMonster]
        )
        root.itemController.replace(model: map, isInsert: true)
        sut.setGame(item: map.copy(), itemId: mapId)
        return Fixture(
            sut: sut,
            mapId: mapId,
            roomA: roomA,
            roomB: roomB,
            playerPin: playerPin,
            roomAMonster: roomAMonster,
            roomBMonster: roomBMonster,
            looseMonster: looseMonster,
            playerCharacterId: playerCharacterId,
            monsterCharacterId: monsterCharacterId
        )
    }

    private static func square(x: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: x, y: 0),
            CGPoint(x: x + 100, y: 0),
            CGPoint(x: x + 100, y: 100),
            CGPoint(x: x, y: 100)
        ]
    }
}
