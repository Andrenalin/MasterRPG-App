// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.27: a remote group event without a counter is refused, so it
/// cannot be handled and relayed again for every copy.
@Suite("Group event counter")
@MainActor
struct GroupEventCounterTests {
    private func roll(counter: Int, masterId: UUID, senderId: UUID) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: masterId,
            sender: GameSenderModel(id: senderId, role: .player, name: "Roller", characterId: nil),
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 1, data: Data([1]))
        )
    }

    @Test("A dice roll with counter 0 is refused, the same roll with a counter is accepted")
    func counterZeroIsRefused() async throws {
        let env = try await LinkedGameEnvironment.create()
        let masterId = env.masterRoot.gameModel.gameConfig.master.id
        let senderId = UUID()
        let connectionId = UUID()

        let withoutCounter = await env.master.accepts(roll(counter: 0, masterId: masterId, senderId: senderId), origin: .direct(connectionId))
        let withCounter = await env.master.accepts(roll(counter: 1, masterId: masterId, senderId: senderId), origin: .direct(connectionId))

        #expect(!withoutCounter)
        #expect(withCounter)
    }
}
#endif
