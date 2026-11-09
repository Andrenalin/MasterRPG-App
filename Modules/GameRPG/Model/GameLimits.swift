// @copyright André Trettin

import CoreRPG
import Foundation

/// Limits that must stay identical wherever they are enforced. The size ceilings of the
/// SharePlay transports are in `GameLimits.SharePlay`, the connection throttling in
/// `GameLimits.Throttle`; `GameLimitsRelationshipTests` pins how they relate to each other.
enum GameLimits {
    /// Largest single Map/Photo/PDF/Space/Audio attachment the game moves around. The LAN framer
    /// (`GameProtocol`) and the SharePlay journal budget both bound messages by it.
    /// 100 MB because SharePlay cannot move larger files, and because the GM decodes (and
    /// relays) a whole frame in memory — a 512 MB ceiling let one peer push it into jetsam.
    static let maximumMessageBytes = 100 * ByteUnit.megabyte

    /// Whether a package of `byteCount` raw bytes may go into the SharePlay Journal, which takes
    /// no attachment over 100 MB. The sender refuses a larger one instead of letting the add
    /// fail or hang, and the receiver ignores one it loaded anyway.
    static func fitsJournalAttachment(byteCount: Int) -> Bool {
        byteCount >= 0 && byteCount <= maximumMessageBytes
    }

    /// Bytes the JSON envelope around an attachment may add to its base64 payload: the sender,
    /// master state, ids and versions. A generous bound, not a measurement.
    static let envelopeAllowanceBytes = 256 * ByteUnit.kibibyte

    /// Whether a message carrying `payloadBytes` of raw attachment data still fits one frame of
    /// `maximumMessageBytes`. The payload is Base64 inside the JSON envelope, which inflates it
    /// by 4/3, so a file of ~75 MB already makes a frame the receiving framer rejects with
    /// `EMSGSIZE`, which ends the player's connection. The send side checks the same constant the
    /// receive side enforces.
    static func fitsOneMessage(payloadBytes: Int) -> Bool {
        guard payloadBytes >= 0, payloadBytes <= maximumMessageBytes else { return false }
        // Base64: four characters for every started group of three bytes.
        let encoded = (payloadBytes + 2) / 3 * 4
        return encoded + envelopeAllowanceBytes <= maximumMessageBytes
    }

    /// Largest payload of a player's group event (a Dice roll, a moved pin, a Space transform).
    /// The master relays these to every peer as soon as their shape is right, so the shape check
    /// bounds the bytes as well: these events are a few hundred bytes to a few kilobytes, and
    /// without a bound one player could have the master forward 100 MB frames to all others.
    static let maximumGroupEventPayloadBytes = 256 * ByteUnit.kibibyte

    /// Cumulative payload bytes the inbound message pipeline may hold queued at once (an empty
    /// queue still admits one message of any size).
    static let maximumQueuedBytes = 300 * ByteUnit.megabyte
    /// Bytes one LAN connection may hold queued for sending: three frames of the largest size.
    /// A connection that falls further behind is dropped, see `ConnectionController.send`.
    static let maximumOutboundQueuedBytes = 3 * maximumMessageBytes

    /// Pauses between restarts of a LAN browser or listener that stopped on its own; the last
    /// value repeats. Shared by `BrowserManager`, `MasterNetworkController` and
    /// `PlayerNetworkController`.
    static let networkRestartDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    /// Listener restarts made at the longest pause before giving up.
    static let extraListenerRestartAttempts = 4

    /// How long an inbound connection may stay unauthenticated, or an outbound dial unconnected,
    /// before it is dropped, so a stalled peer cannot hold a slot.
    static let handshakeDeadline: Duration = .seconds(15)

    /// How long a listener must have run before a later failure counts as a fresh one, so a
    /// listener that was healthy for a while starts its restart pauses from the beginning.
    static let listenerHealthyDuration: Duration = .seconds(120)

    /// How long a lost player's reconnect attempt keeps its place against a newer connection.
    /// A real master authenticates well within this; an attempt that is still unauthenticated
    /// after it gives way, so a stalled peer cannot keep the master out for the whole
    /// handshake deadline.
    static let reconnectHandshakeGrace: Duration = .seconds(3)

    /// The pause before restart `attempt` (0-based).
    static func networkRestartDelay(forAttempt attempt: Int) -> Duration {
        networkRestartDelays[min(max(attempt, 0), networkRestartDelays.count - 1)]
    }

    /// Whether listener restart `attempt` (0-based) is still allowed.
    static func allowsListenerRestart(attempt: Int) -> Bool {
        attempt < networkRestartDelays.count + extraListenerRestartAttempts
    }
}

extension GameLimits {
    /// The ceilings of the SharePlay transports. Messenger carries a package up to
    /// `messengerMessageBytes`; a larger one (up to `maximumMessageBytes`) goes through the
    /// Journal, which takes nothing over `maximumMessageBytes`.
    enum SharePlay {
        /// Largest message Messenger sends as chunks. Below `maximumMessageBytes`: the rest
        /// travels in the Journal.
        static let messengerMessageBytes = 64 * ByteUnit.megabyte
        /// Bytes of chunked messages Messenger may hold queued for sending: two of the largest.
        static let messengerOutstandingBytes = 2 * messengerMessageBytes
        /// Bytes one participant may send to this device within `inboundWindow`, over Messenger
        /// and the Journal together. Several of the largest messages fit, and a sender over it
        /// is dropped undecoded.
        static let inboundBytesPerSender = 512 * ByteUnit.mebibyte
        static let inboundWindow: Duration = .seconds(60)

        /// The pauses between attempts to load an attachment whose upload may not be
        /// downloadable yet; the last value repeats until the load's own deadline.
        static let attachmentRetryDelays: [Duration] = [.milliseconds(250), .seconds(1), .seconds(2)]
        /// A load of an attachment that is still being uploaded fails on every attempt, so after a
        /// short back-off it tries once every few seconds until the caller's deadline.
        static let uploadWaitDelays: [Duration] = attachmentRetryDelays + Array(repeating: .seconds(3), count: 60)
        /// The pauses of a best-effort attachment removal.
        static let cleanupRetryDelays: [Duration] = attachmentRetryDelays + [.seconds(5)]
    }

    /// How the master protects its listener from sources that fail the handshake again and again.
    enum Throttle {
        /// Handshakes that may be unresolved at once across all sources.
        static let maximumPendingHandshakes = 16
        /// Handshakes that may be unresolved at once from a single source.
        static let maximumPendingHandshakesPerSource = 3
        /// Consecutive failures from one source before it starts being throttled.
        static let failureThreshold = 3
        /// Lockout in seconds once the threshold is first reached; doubles per further failure.
        static let baseLockout: Double = 5
        static let maximumLockout: Double = 300
        /// How many distinct sources are tracked at once.
        static let maximumTrackedSources = 256
        /// A source that has been quiet this long starts counting from zero again.
        static let failureDecay: Duration = .seconds(600)
    }
}

/// The game setup's `@AppStorage` keys, kept in one place so a typo can't silently lose the
/// stored value.
enum GameStorageKeys {
    static let lastSelectedGameType = "lastSelectedGameType"
    static let lastAdventureUUID = "lastAdventureUUID"
    static let lastGameMasterUUID = "lastGameMasterUUID"
    static let lastPlayerUUID = "lastPlayerUUID"
    /// A player's companions, per own Character: [Character UUID string: JSON of [TablePlayerModel]].
    static let playerCompanions = "playerCompanions"
}
