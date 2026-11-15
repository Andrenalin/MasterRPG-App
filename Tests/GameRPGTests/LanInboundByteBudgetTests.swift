// @copyright André Trettin

import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_26 §6.6: a LAN connection could make the master decode frames without limit.
@MainActor
@Suite("LAN inbound byte budget")
struct LanInboundByteBudgetTests {
    @Test("A connection over its budget is refused, another connection is not")
    func budgetIsPerConnection() {
        let model = GameNetworkControllerModel(name: "Budget")
        let noisy = UUID()
        let quiet = UUID()
        let start = ContinuousClock.now
        let budget = SharePlayInboundByteBudget.bytesPerSender

        #expect(model.admitsLanFrame(byteCount: budget, from: noisy, now: start))
        #expect(!model.admitsLanFrame(byteCount: 1, from: noisy, now: start + .seconds(1)))
        #expect(model.admitsLanFrame(byteCount: 1_000, from: quiet, now: start + .seconds(1)))
    }

    @Test("The budget renews after the window and is cleared when the game stops")
    func budgetRenewsAndResets() {
        let model = GameNetworkControllerModel(name: "Budget")
        let connection = UUID()
        let start = ContinuousClock.now
        let budget = SharePlayInboundByteBudget.bytesPerSender

        #expect(model.admitsLanFrame(byteCount: budget, from: connection, now: start))
        #expect(model.admitsLanFrame(byteCount: budget, from: connection, now: start + SharePlayInboundByteBudget.window))

        #expect(!model.admitsLanFrame(byteCount: 1, from: connection, now: start + SharePlayInboundByteBudget.window))
        model.resetVersionNotices()
        #expect(model.admitsLanFrame(byteCount: budget, from: connection, now: start + SharePlayInboundByteBudget.window))
    }
}
