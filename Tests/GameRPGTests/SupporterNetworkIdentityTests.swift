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
}
#endif
