// @copyright André Trettin

#if canImport(Testing)
import Foundation
import GroupActivities
import Testing

@testable import CoreRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §3.10 and §3.11.
@Suite("SharePlay lifecycle audit")
@MainActor
struct SharePlayLifecycleAuditTests {

    @Test("waitUntilIdle returns at once when no callback is running")
    func waitUntilIdleWhenIdle() async {
        let coordinator = SharePlaySessionCallbackCoordinator()

        let idle = await coordinator.waitUntilIdle(sessionId: UUID(), timeout: .seconds(30))

        #expect(idle)
    }

    @Test("waitUntilIdle gives up on a callback that never returns (§3.10)")
    func waitUntilIdleTimesOutOnHungCallback() async {
        let coordinator = SharePlaySessionCallbackCoordinator()
        let sessionId = UUID()
        let gate = CallbackGate()
        let hung = Task { @MainActor in
            await coordinator.perform(sessionId: sessionId, shouldContinue: { true }) {
                await gate.wait()
            }
        }
        await Task.yield()

        // No wall-clock bound on the wait: the callback is only released below, so a wait that
        // did not honour its timeout would hang here, and `!idle` proves it gave up. A fixed
        // bound only measures how long a loaded full run starves the main actor, which the
        // timeout task needs (it flaked at 5.01 s).
        let idle = await coordinator.waitUntilIdle(sessionId: sessionId, timeout: .milliseconds(100))

        #expect(!idle)

        // The hung callback is still admitted; releasing it makes a later wait return normally.
        gate.open()
        _ = await hung.value
        let idleAfterwards = await coordinator.waitUntilIdle(sessionId: sessionId, timeout: .seconds(30))
        #expect(idleAfterwards)
    }

    @Test("waitUntilIdle resumes with true when the callback ends before the timeout")
    func waitUntilIdleResumesWhenCallbackEnds() async {
        let coordinator = SharePlaySessionCallbackCoordinator()
        let sessionId = UUID()
        let gate = CallbackGate()
        let callback = Task { @MainActor in
            await coordinator.perform(sessionId: sessionId, shouldContinue: { true }) {
                await gate.wait()
            }
        }
        await Task.yield()

        let waiter = Task { @MainActor in
            await coordinator.waitUntilIdle(sessionId: sessionId, timeout: .seconds(30))
        }
        await Task.yield()
        gate.open()

        #expect(await waiter.value)
        _ = await callback.value
    }

    @Test("repeated Journal drain episodes keep one task handle (§3.11)")
    func journalDrainEpisodesDoNotAccumulateTaskHandles() async {
        let controller = RPGSharePlayController()
        let sessionId = UUID()
        controller.sessionLifecycle.prepare(sessionId: sessionId)
        let baseline = controller.tasks.count

        for _ in 0..<5 {
            controller.receiveJournalSnapshot([], sessionId: sessionId)
            await controller.journalDrainTask?.value
        }

        #expect(controller.tasks.count == baseline + 1)
        #expect(controller.tasks[RPGSharePlayController.journalDrainTaskKey] != nil)
        controller.reset()
    }
}

/// A suspension point a test opens by hand.
@MainActor
private final class CallbackGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
