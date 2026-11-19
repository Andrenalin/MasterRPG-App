// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Synchronization
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
    func scheduledRestartReplacesPendingOne() async {
        var scheduler = ListenerRestartScheduler()
        let counter = RestartCounter()
        let sleeper = ManualSleeper()

        // The first pause is cancelled by the replacement, which is scheduled before it ends.
        #expect(scheduler.schedule(sleep: sleeper.sleep) { counter.runs.append("first") })
        #expect(scheduler.schedule(sleep: sleeper.sleep) { counter.runs.append("second") })
        #expect(await awaitCondition { sleeper.durations.count == 2 })
        #expect(sleeper.durations == Array(GameLimits.networkRestartDelays.prefix(2)))

        sleeper.release(1)
        #expect(await awaitCondition { counter.runs == ["second"] })

        // Even when its pause ends too, the replaced restart does not run.
        sleeper.release(0)
        #expect(await conditionHolds { counter.runs == ["second"] })
        scheduler.cancel()
    }

    @Test("Cancel drops the pending restart")
    func cancelDropsPendingRestart() async {
        var scheduler = ListenerRestartScheduler()
        let counter = RestartCounter()
        let sleeper = ManualSleeper()

        #expect(scheduler.schedule(sleep: sleeper.sleep) { counter.runs.append("restart") })
        #expect(await awaitCondition { sleeper.durations.count == 1 })
        scheduler.cancel()
        sleeper.release(0)

        #expect(await conditionHolds { counter.runs.isEmpty })
    }
}

@MainActor
private final class RestartCounter {
    var runs: [String] = []
}

/// A `Task.sleep` stand-in that waits until the test releases it, and throws when cancelled.
private final class ManualSleeper: Sendable {
    private struct State {
        var durations: [Duration] = []
        var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
        var released: Set<Int> = []
        var cancelled: Set<Int> = []
    }

    private let state = Mutex(State())

    /// The pause of every call so far, in call order.
    var durations: [Duration] { state.withLock { $0.durations } }

    @Sendable
    func sleep(_ duration: Duration) async throws {
        let index = state.withLock { state -> Int in
            state.durations.append(duration)
            return state.durations.count - 1
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome = state.withLock { state -> Result<Void, any Error>? in
                    if state.released.contains(index) { return .success(()) }
                    if state.cancelled.contains(index) { return .failure(CancellationError()) }
                    state.waiters[index] = continuation
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let waiter = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                state.cancelled.insert(index)
                return state.waiters.removeValue(forKey: index)
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// Ends the pause of the call at `index`.
    func release(_ index: Int) {
        let waiter = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            state.released.insert(index)
            return state.waiters.removeValue(forKey: index)
        }
        waiter?.resume()
    }
}
#endif
