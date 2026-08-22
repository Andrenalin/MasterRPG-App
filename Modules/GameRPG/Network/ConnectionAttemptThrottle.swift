// @copyright André Trettin

import Foundation
import Network

/// Tracks per-source connection failures and enforces a lockout after repeated
/// bad-passcode attempts — the residual gap noted in CODE_AUDIT §6.1: the 4-digit
/// join code (10,000 combinations) had no connection-attempt throttling at all,
/// so a wrong guess could be retried immediately and indefinitely.
///
/// The threshold is deliberately 3, not 1: the first connection attempt from a
/// peer is commonly `GameJoinCodeModel.lastUsedMasterJoinCode` retried
/// automatically, and a second may be a legitimate manual retry after a typo
/// (see `BrowserRowView`). Only a 3rd consecutive failure from the same source
/// starts a lockout, so ordinary reconnects and typos are never penalized —
/// only a source that's actually guessing.
actor ConnectionAttemptThrottle {
    private struct State {
        var consecutiveFailures = 0
        var lockedUntil: ContinuousClock.Instant?
        var lastActivity: ContinuousClock.Instant
    }

    /// Consecutive failures from one source before it starts being throttled.
    static let failureThreshold = 3
    /// Lockout once the threshold is first reached; doubles per additional
    /// failure beyond the threshold, capped at `maximumLockout`.
    private static let baseLockout: Double = 5
    private static let maximumLockout: Double = 300
    /// Caps how many distinct sources are tracked at once. A source that
    /// fails once or twice and never authenticates (a scanner, a
    /// misconfigured device, a mistyped code someone gave up on) otherwise
    /// leaves a permanent entry for the life of the hosting session — nothing
    /// else ever prunes it. See CODE_AUDIT §6.4.
    private static let maximumTrackedSources = 256

    private var sources: [String: State] = [:]

    /// Whether a new connection attempt from `source` should be allowed right
    /// now. `now` is injectable for deterministic tests; production always
    /// measures against the real continuous clock so a wall-clock change
    /// (manual adjustment, NTP sync, DST) can neither shorten nor extend an
    /// active lockout — matching `SharePlayMapRecoveryTracker`'s own use of
    /// `ContinuousClock` for the same reason. See CODE_AUDIT §3.2.
    func shouldAllow(source: String, at now: ContinuousClock.Instant? = nil) -> Bool {
        guard let lockedUntil = sources[source]?.lockedUntil else { return true }
        return (now ?? ContinuousClock().now) >= lockedUntil
    }

    /// Records a failed handshake/authentication from `source`, starting or
    /// extending a lockout once `failureThreshold` consecutive failures accrue.
    func recordFailure(source: String, at now: ContinuousClock.Instant? = nil) {
        let now = now ?? ContinuousClock().now
        var state = sources[source] ?? State(lastActivity: now)
        state.consecutiveFailures += 1
        state.lastActivity = now
        if state.consecutiveFailures >= Self.failureThreshold {
            let extraFailures = state.consecutiveFailures - Self.failureThreshold
            let lockout = min(Self.baseLockout * pow(2, Double(extraFailures)), Self.maximumLockout)
            state.lockedUntil = now.advanced(by: .seconds(lockout))
        }
        sources[source] = state
        evictIfNeeded(excluding: source)
    }

    /// Clears any tracked failures for `source` after it authenticates successfully.
    func recordSuccess(source: String) {
        sources.removeValue(forKey: source)
    }

    /// Evicts the least-recently-active source once the tracked count exceeds
    /// `maximumTrackedSources`. See CODE_AUDIT §6.4.
    private func evictIfNeeded(excluding source: String) {
        while sources.count > Self.maximumTrackedSources {
            guard let oldest = sources
                .filter({ $0.key != source })
                .min(by: { $0.value.lastActivity < $1.value.lastActivity })?
                .key
            else { return }
            sources.removeValue(forKey: oldest)
        }
    }
}

extension NWEndpoint {
    /// A stable per-host key for connection-attempt throttling. Deliberately
    /// excludes the port: a retry from the same peer uses a new ephemeral one,
    /// and including it would let a retry dodge the throttle entirely.
    var throttleSourceKey: String? {
        guard case .hostPort(let host, _) = self else { return nil }
        return "\(host)"
    }
}
