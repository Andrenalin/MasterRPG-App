// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_21 §6.5: a completed SharePlay package was decoded however often a participant
/// sent one.
@Suite("SharePlay inbound byte budget")
@MainActor
struct SharePlayInboundByteBudgetTests {
    // The results are taken outside `#expect`: the macro captures its operands immutably, and
    // `admit` is mutating.
    @Test("A sender over its budget is refused until the window has passed")
    func budgetPerWindow() {
        var budget = SharePlayInboundByteBudget()
        let sender = UUID()
        let start = ContinuousClock.now
        let half = SharePlayInboundByteBudget.bytesPerSender / 2

        let first = budget.admit(half, from: sender, now: start)
        let second = budget.admit(half, from: sender, now: start + .seconds(1))
        let overBudget = budget.admit(1, from: sender, now: start + .seconds(2))
        // A refused package does not count against the budget.
        let stillOverBudget = budget.admit(1, from: sender, now: start + .seconds(59))
        let afterWindow = budget.admit(half, from: sender, now: start + .seconds(60))

        #expect(first)
        #expect(second)
        #expect(!overBudget)
        #expect(!stillOverBudget)
        #expect(afterWindow)
    }

    @Test("Each sender has its own budget, and a reset clears all of them")
    func budgetPerSender() {
        var budget = SharePlayInboundByteBudget()
        let first = UUID()
        let second = UUID()
        let now = ContinuousClock.now
        let all = SharePlayInboundByteBudget.bytesPerSender

        let firstAdmitted = budget.admit(all, from: first, now: now)
        let firstRefused = budget.admit(1, from: first, now: now)
        let secondAdmitted = budget.admit(all, from: second, now: now)
        budget.reset()
        let firstAfterReset = budget.admit(all, from: first, now: now)

        #expect(firstAdmitted)
        #expect(!firstRefused)
        #expect(secondAdmitted)
        #expect(firstAfterReset)
    }
}
#endif
