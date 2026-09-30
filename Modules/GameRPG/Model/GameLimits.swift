// @copyright André Trettin

import Foundation

/// Limits that must stay identical wherever they are enforced. See CODE_AUDIT_15 §9.20.
enum GameLimits {
    /// Largest single Map/Photo/PDF/Space/Audio attachment the game moves around. The LAN framer
    /// (`GameProtocol`) and the SharePlay journal budget both bound messages by it.
    /// 100 MB because SharePlay cannot move larger files, and because the GM decodes (and
    /// relays) a whole frame in memory — a 512 MB ceiling let one peer push it into jetsam.
    /// See CODE_AUDIT_17 §6.2.
    static let maximumMessageBytes = 100_000_000

    /// Cumulative payload bytes the inbound message pipeline may hold queued at once (an empty
    /// queue still admits one message of any size). See CODE_AUDIT_16 §6.3.
    static let maximumQueuedBytes = 300_000_000

    /// Pauses between restarts of a LAN browser or listener that stopped on its own; the last
    /// value repeats. Shared by `BrowserManager`, `MasterNetworkController` and
    /// `PlayerNetworkController`. See CODE_AUDIT_18 §9.17.
    static let networkRestartDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    /// Listener restarts made at the longest pause before giving up.
    static let extraListenerRestartAttempts = 4

    /// How long an inbound connection may stay unauthenticated, or an outbound dial unconnected,
    /// before it is dropped, so a stalled peer cannot hold a slot.
    static let handshakeDeadline: Duration = .seconds(15)

    /// The pause before restart `attempt` (0-based).
    static func networkRestartDelay(forAttempt attempt: Int) -> Duration {
        networkRestartDelays[min(max(attempt, 0), networkRestartDelays.count - 1)]
    }

    /// Whether listener restart `attempt` (0-based) is still allowed.
    static func allowsListenerRestart(attempt: Int) -> Bool {
        attempt < networkRestartDelays.count + extraListenerRestartAttempts
    }
}

/// The game setup's `@AppStorage` keys, kept in one place so a typo can't silently lose the
/// stored value. See CODE_AUDIT_19 §9.8.
enum GameStorageKeys {
    static let lastSelectedGameType = "lastSelectedGameType"
    static let lastAdventureUUID = "lastAdventureUUID"
    static let lastGameMasterUUID = "lastGameMasterUUID"
    static let lastPlayerUUID = "lastPlayerUUID"
}
