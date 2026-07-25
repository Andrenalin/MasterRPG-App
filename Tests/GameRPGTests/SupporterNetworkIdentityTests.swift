// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@Suite("Supporter network identity")
struct SupporterNetworkIdentityTests {
    @Test func senderRoundTripsSupporterTier() throws {
        let sender = GameSenderModel(
            id: UUID(),
            role: .player,
            name: "Ari",
            characterId: UUID(),
            supporterTier: .gold
        )

        let encoded = try JSONEncoder().encode(sender)
        let decoded = try JSONDecoder().decode(GameSenderModel.self, from: encoded)

        #expect(decoded == sender)
        #expect(decoded.playerModel.supporterTier == .gold)
    }

    @Test func legacySenderDefaultsToNoSupporterTier() throws {
        struct LegacySender: Encodable {
            let id: UUID
            let role: GameType
            let name: String
            let characterId: UUID?
        }

        let encoded = try JSONEncoder().encode(
            LegacySender(
                id: UUID(),
                role: .player,
                name: "Legacy Ari",
                characterId: UUID()
            )
        )
        let decoded = try JSONDecoder().decode(GameSenderModel.self, from: encoded)

        #expect(decoded.supporterTier == .none)
    }

    @Test @MainActor
    func activePlayerTierUpdatesImmediately() {
        let playerID = UUID()
        let model = GameRootModel()
        model.gameConfig = GameConfigModel(
            id: playerID,
            state: .started,
            master: MasterGameModel(
                id: UUID(),
                type: .master,
                name: "Game Master"
            )
        )
        model.gameRoster = GameRosterModel(
            players: [
                PlayerGameModel(
                    id: playerID,
                    type: .player,
                    name: "Ari",
                    supporterTier: .none
                )
            ]
        )

        model.updateLocalSupporterTier(.gold)

        #expect(model.gamePlayer.supporterTier == .gold)
    }

    @Test @MainActor
    func activeMasterTierUpdatesImmediately() {
        let masterID = UUID()
        let model = GameRootModel()
        model.gameConfig = GameConfigModel(
            id: masterID,
            state: .started,
            master: MasterGameModel(
                id: masterID,
                type: .master,
                name: "Game Master",
                supporterTier: .none
            )
        )

        model.updateLocalSupporterTier(.silver)

        #expect(model.gameConfig.master.supporterTier == .silver)
    }

    @Test @MainActor
    func masterBroadcastDoesNotOverwriteLocalEntitlement() {
        let playerID = UUID()
        let masterID = UUID()
        let model = GameRootModel()
        model.gameConfig = GameConfigModel(
            id: playerID,
            state: .started,
            master: MasterGameModel(
                id: masterID,
                type: .master,
                name: "Game Master"
            )
        )
        model.gameRoster = GameRosterModel(
            players: [
                PlayerGameModel(
                    id: playerID,
                    type: .player,
                    name: "Ari",
                    supporterTier: .gold
                )
            ]
        )

        model.applyMasterBroadcast(
            masterId: masterID,
            masterName: "Game Master",
            state: GameMasterStateModel(
                state: .started,
                players: [
                    PlayerGameModel(
                        id: playerID,
                        type: .player,
                        name: "Ari",
                        supporterTier: .none
                    )
                ]
            )
        )

        #expect(model.gamePlayer.supporterTier == .gold)
    }
}
#endif
