// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.21: with player dice off, a group roll of another player is not
/// applied and not answered.
@Suite("Player dice gate")
@MainActor
struct PlayerDiceGateTests {
    private func roll(from senderId: UUID, targetId: UUID?) -> GameNetworkModel {
        GameNetworkModel(
            counter: 3,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            masterId: UUID(),
            sender: GameSenderModel(id: senderId, role: .player, name: "Other", characterId: nil),
            targetId: targetId,
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 1, data: Data([1]))
        )
    }

    @Test("A gated group roll gets no answer; one addressed to this device gets a failure")
    func gatedRollIsNotAnswered() async throws {
        let env = try await LinkedGameEnvironment.create()
        let player = try await env.addPlayer(named: "Gated")
        player.root.gameModel.gameControl.features = GameFeatureModel(diceMaster: true, dicePlayers: false)

        let groupRoll = try await player.controller.handleDice(roll(from: UUID(), targetId: nil))
        let addressed = try await player.controller.handleDice(roll(from: UUID(), targetId: player.config.id))

        #expect(groupRoll == nil)
        #expect(addressed?.subType == .failed)
    }

    @Test("A message is forwarded to the proxy clients once per key, until the master's counters restart (§5.22)")
    func forwardedOncePerKey() {
        let model = PlayerControllerModel()
        let key = GameMessageKey(model: roll(from: UUID(), targetId: nil))

        #expect(model.claimProxyForward(key))
        #expect(!model.claimProxyForward(key))
        model.resetMasterSequences()
        #expect(model.claimProxyForward(key))
    }
}
#endif
