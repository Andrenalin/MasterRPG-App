// @copyright André Trettin

import Foundation
import Network

/// Bundles a `ConnectionAttemptThrottle` with the per-connection bookkeeping
/// every listener-accepting controller needs around it: remember which
/// `ConnectionController.ID` is provisionally tied to which throttle source
/// while its handshake is still in flight, then resolve that pending entry to
/// a success or failure once the handshake concludes.
///
/// `MasterNetworkController` and `PlayerNetworkController` previously
/// hand-implemented this identical three-step lifecycle (register on new/
/// restarted connection, record failure + clear on a fresh handshake failing,
/// record success + clear on ready) independently at each call site — a
/// future correctness fix to this security-relevant bookkeeping had to be
/// reapplied and reverified in two places. See CODE_AUDIT §9.7.
actor ConnectionThrottleTracker {
    private let throttle = ConnectionAttemptThrottle()
    private var pendingSources: [ConnectionController.ID: String] = [:]

    /// Whether a new connection attempt from `endpoint` should be admitted.
    /// An endpoint with no derivable `throttleSourceKey` is always admitted —
    /// matching `ConnectionAttemptThrottle`'s own source-less behavior.
    func shouldAllow(endpoint: NWEndpoint) async -> Bool {
        guard let source = endpoint.throttleSourceKey else { return true }
        return await throttle.shouldAllow(source: source)
    }

    /// Ties `id` to `endpoint`'s throttle source while its handshake is in
    /// flight, so a later `resolve(id:succeeded:)` or `clear(id:)` knows what
    /// to do. A no-op for an endpoint with no derivable source.
    func register(id: ConnectionController.ID, endpoint: NWEndpoint) {
        guard let source = endpoint.throttleSourceKey else { return }
        pendingSources[id] = source
    }

    /// Resolves a pending connection's outcome: `true` records a success
    /// (clearing any prior failures for that source), `false` records a
    /// failure (possibly starting/extending a lockout). A connection with no
    /// pending entry — never registered, or already resolved — is a no-op.
    func resolve(id: ConnectionController.ID, succeeded: Bool) async {
        guard let source = pendingSources.removeValue(forKey: id) else { return }
        if succeeded {
            await throttle.recordSuccess(source: source)
        } else {
            await throttle.recordFailure(source: source)
        }
    }

    /// Clears a pending entry without recording either outcome — used when a
    /// connection ends for a reason that isn't itself evidence of a
    /// bad-passcode attempt (e.g. a clean peer disconnect).
    func clear(id: ConnectionController.ID) {
        pendingSources.removeValue(forKey: id)
    }

    /// Drops every pending (not-yet-resolved) connection, without touching
    /// the underlying throttle's recorded failures/lockouts — those persist
    /// across a streaming restart on purpose, so a bad-faith source doesn't
    /// get a free pass just because hosting was toggled off and back on.
    /// Used when a listener-owning controller tears down all of its
    /// connections at once (e.g. `MasterNetworkController.resetConnections()`).
    func clearAllPending() {
        pendingSources.removeAll()
    }
}
