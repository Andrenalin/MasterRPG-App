// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import PhotoRPG
import SwiftUI

public enum BattleRoundPreviewData {
    @MainActor
    public static func model() -> BattleRoundModel {
        let model = BattleRoundModel()
        apply(to: model)
        return model
    }

    @MainActor
    public static func apply(to model: BattleRoundModel) {
        apply(Fixture(), to: model)
    }

    /// Installs the same pins into the active preview map so Game-module
    /// previews exercise the real battle actions instead of a detached model.
    @MainActor
    public static func apply(to root: MapRootModel) {
        let fixture = Fixture()
        let room = MapEntryModel(
            id: identifier(0x86),
            name: "Ruined Gatehouse",
            content: "A battle-ready room used by Game previews.",
            coordinates: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 600, y: 0),
                CGPoint(x: 600, y: 500),
                CGPoint(x: 0, y: 500)
            ],
            focused: true
        )
        let map = MapModel(
            id: MapRootModel.previewValueId,
            name: "Battle at the Shattered Crown",
            description: "A complete Game preview map with players and monsters.",
            entries: [room],
            width: 800,
            height: 600,
            mapPins: (fixture.players + fixture.monsters).map(\.pin)
        )
        root.gameController.setGame(item: map, itemId: map.id)
        apply(fixture, to: root.mapGameControllable.battleRoundModel)
    }

    @MainActor
    private static func apply(_ fixture: Fixture, to model: BattleRoundModel) {
        let players = fixture.players
        let monsters = fixture.monsters

        model.begin(
            mapId: MapRootModel.previewValueId,
            players: players,
            roomCombatants: monsters,
            initiativeOrder: .descending
        )

        let initiatives = [
            players[0].id: 21,
            monsters[0].id: 18,
            players[1].id: 14,
            monsters[1].id: 11,
            monsters[2].id: 7
        ]
        for (combatantId, initiative) in initiatives {
            _ = model.setInitiative(initiative, for: combatantId)
        }

        _ = model.activateAttacker(players[0].id)
        _ = model.synchronize(pins: (players + monsters).map(\.pin))
        _ = model.addRoll(
            combatantId: players[0].id,
            total: 17,
            expression: "1d20 + 4",
            timestamp: Date(timeIntervalSince1970: 1_767_225_600)
        )
        _ = model.addRoll(
            combatantId: monsters[0].id,
            total: 9,
            expression: "1d12 + 2",
            timestamp: Date(timeIntervalSince1970: 1_767_225_601)
        )
        _ = model.selectRollRecipient(monsters[0].id)
    }

    @MainActor
    private struct Fixture {
        let players: [BattleCombatant]
        let monsters: [BattleCombatant]

        init() {
            players = [
                combatant(
                    id: identifier(0x71),
                    pinId: identifier(0x81),
                    name: "Aria Swiftwind",
                    color: .blue,
                    sourceCharacterId: CharacterRootModel.previewValueId,
                    isPlayer: true
                ),
                combatant(
                    id: identifier(0x72),
                    pinId: identifier(0x82),
                    name: "Borin Stoneguard",
                    color: .green,
                    sourceCharacterId: nil,
                    isPlayer: true
                )
            ]
            monsters = [
                combatant(
                    id: identifier(0x73),
                    pinId: identifier(0x83),
                    name: "Goblin Captain",
                    color: .red,
                    sourceCharacterId: nil,
                    isHighlighted: true
                ),
                combatant(
                    id: identifier(0x74),
                    pinId: identifier(0x84),
                    name: "Skeleton Archer",
                    color: .orange,
                    sourceCharacterId: nil,
                    isHighlighted: true
                ),
                combatant(
                    id: identifier(0x75),
                    pinId: identifier(0x85),
                    name: "Fallen Cultist",
                    color: .purple,
                    sourceCharacterId: nil,
                    isDead: true
                )
            ]
        }
    }

    @MainActor
    private static func combatant(
        id: UUID,
        pinId: UUID,
        name: String,
        color: Color,
        sourceCharacterId: UUID?,
        isPlayer: Bool = false,
        isHighlighted: Bool = false,
        isDead: Bool = false
    ) -> BattleCombatant {
        BattleCombatant(
            id: id,
            pin: MapPinModel(
                id: pinId,
                name: name,
                color: color,
                photoId: PhotoRootModel.previewPhotoId,
                characterId: sourceCharacterId,
                isPlayer: isPlayer,
                isDead: isDead,
                isHighlighted: isHighlighted
            ),
            sourceCharacterId: sourceCharacterId,
            gameCharacterId: nil,
            isPlayer: isPlayer
        )
    }

    nonisolated private static func identifier(_ finalByte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
    }
}
