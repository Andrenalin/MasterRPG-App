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
        var lockedUntil: Date?
    }

    /// Consecutive failures from one source before it starts being throttled.
    static let failureThreshold = 3
    /// Lockout once the threshold is first reached; doubles per additional
    /// failure beyond the threshold, capped at `maximumLockout`.
    private static let baseLockout: TimeInterval = 5
    private static let maximumLockout: TimeInterval = 300

    private var sources: [String: State] = [:]

    /// Whether a new connection attempt from `source` should be allowed right now.
    func shouldAllow(source: String) -> Bool {
        guard let lockedUntil = sources[source]?.lockedUntil else { return true }
        return Date.now >= lockedUntil
    }

    /// Records a failed handshake/authentication from `source`, starting or
    /// extending a lockout once `failureThreshold` consecutive failures accrue.
    func recordFailure(source: String) {
        var state = sources[source] ?? State()
        state.consecutiveFailures += 1
        if state.consecutiveFailures >= Self.failureThreshold {
            let extraFailures = state.consecutiveFailures - Self.failureThreshold
            let lockout = min(Self.baseLockout * pow(2, Double(extraFailures)), Self.maximumLockout)
            state.lockedUntil = Date.now.addingTimeInterval(lockout)
        }
        sources[source] = state
    }

    /// Clears any tracked failures for `source` after it authenticates successfully.
    func recordSuccess(source: String) {
        sources.removeValue(forKey: source)
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
