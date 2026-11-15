// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §3.9, §3.10, §3.15, §3.16: link actions are owned, so a game end can cancel them.
@MainActor
struct LinkActionTasksTests {
    @Test func cancelAllStopsARunningAction() async {
        var finished = false
        LinkActionTasks.run {
            try await Task.sleep(for: .seconds(30))
            finished = true
        }
        LinkActionTasks.cancelAll()
        for _ in 0..<20 { await Task.yield() }
        #expect(!finished)
    }

    @Test func aFinishedActionRunsAndIsForgotten() async {
        var finished = false
        LinkActionTasks.run { finished = true }
        for _ in 0..<50 where !finished { await Task.yield() }
        #expect(finished)
    }

    @Test func aFailingActionDoesNotCrashOrStayRegistered() async {
        struct Failure: Error {}
        var ran = false
        LinkActionTasks.run {
            ran = true
            throw Failure()
        }
        for _ in 0..<50 where !ran { await Task.yield() }
        #expect(ran)
    }
}
#endif
