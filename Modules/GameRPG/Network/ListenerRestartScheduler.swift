// @copyright André Trettin

import Foundation

/// The restart policy of a listener that stopped on its own: pauses that grow with every
/// attempt (`GameLimits.networkRestartDelays`), a fresh start of the count once a listener ran
/// healthy for `GameLimits.listenerHealthyDuration`, and at most one pending restart.
/// `MasterNetworkController` and `PlayerNetworkController` share it, so the two cannot drift.
@MainActor
struct ListenerRestartScheduler {
    private(set) var attempt = 0
    private var startedAt: ContinuousClock.Instant?
    private var task: Task<Void, Never>?

    /// A listener was created. Call it for every listener, also a restarted one: the healthy
    /// run is measured from here.
    mutating func listenerStarted(at now: ContinuousClock.Instant = .now) {
        startedAt = now
    }

    /// The pause before the next restart, or `nil` once the attempts are used up. Counts the
    /// attempt; a listener that ran healthy before it failed starts the count from zero.
    mutating func nextDelay(now: ContinuousClock.Instant = .now) -> Duration? {
        if let startedAt, now - startedAt > GameLimits.listenerHealthyDuration {
            attempt = 0
        }
        guard GameLimits.allowsListenerRestart(attempt: attempt) else { return nil }
        defer { attempt += 1 }
        return GameLimits.networkRestartDelay(forAttempt: attempt)
    }

    /// Runs `restart` after the next pause, replacing a restart that is still pending. Returns
    /// `false`, scheduling nothing, once the attempts are used up.
    ///
    /// - Parameter sleep: waits out the pause. Tests pass a sleeper they release by hand instead
    ///   of waiting seconds; it must throw when its task is cancelled.
    @discardableResult
    mutating func schedule(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        restart: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard let delay = nextDelay() else { return false }
        task?.cancel()
        task = Task { @MainActor in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            await restart()
        }
        return true
    }

    /// Drops a pending restart and starts counting from zero.
    mutating func reset() {
        cancel()
        attempt = 0
    }

    /// Drops a pending restart; the count stays.
    mutating func cancel() {
        task?.cancel()
        task = nil
    }
}
