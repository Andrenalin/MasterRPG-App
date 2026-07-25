// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

@Suite("Supporter tier")
struct SupporterTierTests {
    @Test(arguments: SupporterTier.allCases)
    func supporterTierRoundTrips(_ tier: SupporterTier) throws {
        let encoded = try JSONEncoder().encode(tier)
        let decoded = try JSONDecoder().decode(SupporterTier.self, from: encoded)

        #expect(decoded == tier)
    }

    @Test func highestTierWins() {
        let owned: [SupporterTier] = [.silver, .bronze, .gold]

        #expect(owned.max() == .gold)
    }

    @Test func legacyPlayerDefaultsToNoSupporterTier() throws {
        struct LegacyPlayer: Encodable {
            let id: UUID
            let type: GameType
            let name: String
            let characterId: UUID?
        }

        let encoded = try JSONEncoder().encode(
            LegacyPlayer(
                id: UUID(),
                type: .player,
                name: "Legacy Player",
                characterId: UUID()
            )
        )
        let decoded = try JSONDecoder().decode(PlayerGameModel.self, from: encoded)

        #expect(decoded.supporterTier == .none)
    }

    @Test func legacyMasterDefaultsToNoSupporterTier() throws {
        struct LegacyMaster: Encodable {
            let id: UUID
            let type: GameType
            let name: String
            let adventureId: UUID?
            let adventureTitle: String?
        }

        let encoded = try JSONEncoder().encode(
            LegacyMaster(
                id: UUID(),
                type: .master,
                name: "Legacy Master",
                adventureId: UUID(),
                adventureTitle: "The Old Road"
            )
        )
        let decoded = try JSONDecoder().decode(MasterGameModel.self, from: encoded)

        #expect(decoded.supporterTier == .none)
    }
}
#endif
