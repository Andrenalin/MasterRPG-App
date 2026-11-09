// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// The restart policy master and player share for a listener that stopped on its own.
@MainActor
@Suite("Listener restart scheduler")
struct ListenerRestartSchedulerTests {
    let start = ContinuousClock.now

    @Test("The pauses grow and the last one repeats until the attempts are used up")
    func pausesGrowUntilTheAttemptsAreUsedUp() {
        var scheduler = ListenerRestartScheduler()
        scheduler.listenerStarted(at: start)
        let total = GameLimits.networkRestartDelays.count + GameLimits.extraListenerRestartAttempts

        var delays: [Duration] = []
        while let delay = scheduler.nextDelay(now: start) {
            delays.append(delay)
        }

        #expect(delays.count == total)
        #expect(Array(delays.prefix(GameLimits.networkRestartDelays.count)) == GameLimits.networkRestartDelays)
        #expect(delays.suffix(GameLimits.extraListenerRestartAttempts).allSatisfy { $0 == GameLimits.networkRestartDelays.last })
        #expect(scheduler.nextDelay(now: start) == nil)
    }

    @Test("A listener that ran healthy starts the count from zero")
    func healthyRunStartsTheCountAgain() {
        var scheduler = ListenerRestartScheduler()
        scheduler.listenerStarted(at: start)
        _ = scheduler.nextDelay(now: start)
        _ = scheduler.nextDelay(now: start)

        let afterHealthyRun = scheduler.nextDelay(now: start + GameLimits.listenerHealthyDuration + .seconds(1))

        #expect(afterHealthyRun == GameLimits.networkRestartDelays.first)
        #expect(scheduler.attempt == 1)
    }

    @Test("A restarted listener is measured from its own start, not from the first one")
    func restartedListenerIsMeasuredFromItsOwnStart() {
        var scheduler = ListenerRestartScheduler()
        scheduler.listenerStarted(at: start)
        _ = scheduler.nextDelay(now: start)
        // The first listener failed after a long time, the restarted one fails right away.
        let restartedAt = start + GameLimits.listenerHealthyDuration * 2
        scheduler.listenerStarted(at: restartedAt)

        let delay = scheduler.nextDelay(now: restartedAt + .seconds(1))

        #expect(delay == GameLimits.networkRestartDelays[1])
    }

    @Test("Reset starts counting from zero")
    func resetStartsFromZero() {
        var scheduler = ListenerRestartScheduler()
        _ = scheduler.nextDelay(now: start)
        _ = scheduler.nextDelay(now: start)

        scheduler.reset()

        #expect(scheduler.attempt == 0)
        #expect(scheduler.nextDelay(now: start) == GameLimits.networkRestartDelays.first)
    }

    @Test("A scheduled restart runs once, and a newer one replaces a pending one")
    func scheduledRestartReplacesPendingOne() async throws {
        var scheduler = ListenerRestartScheduler()
        let counter = RestartCounter()

        // The first pause is a second long: the replacement (the second attempt, two seconds) is
        // scheduled before it ends.
        #expect(scheduler.schedule { counter.runs.append("first") })
        #expect(scheduler.schedule { counter.runs.append("second") })
        let deadline = ContinuousClock.now + .seconds(15)
        while counter.runs.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        // Long enough for a first restart that was not replaced to have run as well.
        try await Task.sleep(for: .milliseconds(1500))

        #expect(counter.runs == ["second"])
        scheduler.cancel()
    }

    @Test("Cancel drops the pending restart")
    func cancelDropsPendingRestart() async throws {
        var scheduler = ListenerRestartScheduler()
        let counter = RestartCounter()

        #expect(scheduler.schedule { counter.runs.append("restart") })
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(1500))

        #expect(counter.runs.isEmpty)
    }
}

@MainActor
private final class RestartCounter {
    var runs: [String] = []
}
#endif
