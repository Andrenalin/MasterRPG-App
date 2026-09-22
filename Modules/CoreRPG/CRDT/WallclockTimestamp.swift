//
//  WallclockTimestamp.swift
//

import Foundation
import Synchronization

/// Hands out `Date()`-based timestamps for new local writes, guaranteed to
/// strictly increase within this process even when two writes land in the
/// same underlying clock tick — `Date()`'s effective resolution is coarser
/// than two back-to-back calls on modern hardware. Without this, two
/// independently value-copied `LWWRegister`s that still share an actor ID
/// (e.g. `var a = original; var b = original`, each later mutated locally)
/// can tie on both clock *and* actor ID, and `merged(with:)`'s tie-break
/// then falls back to picking whichever operand happens to be `other` —
/// silently discarding whichever write actually happened later.
///
/// The values handed out remain real wall-clock time, nudged forward by at
/// most `nextUp`'s epsilon, so ordering against another device's genuinely
/// distinct `Date()`-based timestamp is unaffected — this only breaks local
/// ties. See CODE_AUDIT_10 §3 follow-up.
///
/// `public` only because it backs a default argument value on `public`
/// initializers below — not intended as a general-purpose API.
public enum MonotonicWallClock {
    private static let lastIssued = Mutex<TimeInterval>(0)

    public static func now() -> TimeInterval {
        lastIssued.withLock { last in
            let candidate = Date().timeIntervalSinceReferenceDate
            let issued = candidate > last ? candidate : last.nextUp
            last = issued
            return issued
        }
    }

    /// Advances the local clock to a timestamp seen from another device (hybrid logical
    /// clock). Every later local write then sorts after it, so a device whose wall clock runs
    /// ahead — or a crafted payload with a far-future timestamp — can win the merge it
    /// arrived in, but can no longer freeze the item against the edits that follow.
    /// Non-finite values are ignored and finite values are capped at "now plus a small skew",
    /// so a crafted far-future clock (up to `greatestFiniteMagnitude`, whose `nextUp` is
    /// infinity and cannot be JSON-encoded) cannot poison the process clock.
    /// See CODE_AUDIT_15 §5.3 and CODE_AUDIT_16 §5.2.
    public static func observe(_ remoteTimestamp: TimeInterval) {
        guard remoteTimestamp.isFinite else { return }
        let bounded = bounded(remoteTimestamp)
        lastIssued.withLock { last in
            if bounded > last {
                last = bounded
            }
        }
    }

    /// `remoteTimestamp` capped at "now plus the allowed skew".
    static func bounded(_ remoteTimestamp: TimeInterval, now: TimeInterval = Date().timeIntervalSinceReferenceDate) -> TimeInterval {
        min(remoteTimestamp, now + maximumObservedSkew)
    }

    /// How far ahead of the local clock a remote timestamp may pull it (or, when decoded, be
    /// accepted): a day covers a badly misconfigured device clock, while a crafted value can no
    /// longer push the clock toward infinity.
    static let maximumObservedSkew: TimeInterval = 86_400
}

/// A wall-clock timestamp for a specific actor.
///
/// The comparable value of the actor identity is used to deterministically order of wallclock timestamps in the (unlikely, but possible) scenario
/// where the clock value is identical. These scenarios happen when two independent CRDTs update internal values
/// "at the same time".
public struct WallclockTimestamp<ActorID: Hashable & Comparable>: Identifiable, Comparable {
    internal var clock: TimeInterval
    internal var actorId: ActorID

    /// A stable, unique identity for the wallclock timestamp.
    public var id: String {
        description
    }

    /// Returns a Boolean value indicating whether the value of the first timestamp is less than that of the second timestamp.
    ///
    /// Timestamps are first compared by an internal `clock` value, and uses the provided actor to deterministically order values when the clocks are identical.
    /// This assures that timestamps are partially order-able to satisfy  conformance to ``CRDT/PartiallyOrderable``.
    /// - Parameters:
    ///   - lhs: The first timestamp.
    ///   - rhs: The second timestamp.
    public static func < (lhs: WallclockTimestamp, rhs: WallclockTimestamp) -> Bool {
        (lhs.clock, lhs.id) < (rhs.clock, rhs.id)
    }

    /// Create a new Lamport timestamp with the actor identity you provide.
    /// - Parameters:
    ///   - clock: An optional initial clock value, that otherwise defaults to a value determined by the current time.
    ///   - actorId: The actor identity for the timestamp.
    public init(actorId: ActorID, timestamp: TimeInterval = MonotonicWallClock.now()) {
        clock = timestamp
        self.actorId = actorId
    }
}

extension WallclockTimestamp: Codable where ActorID: Codable {
    private enum CodingKeys: String, CodingKey {
        case clock
        case actorId
    }

    /// Same wire format as the synthesized conformance, except that a non-finite clock
    /// (NaN/infinity from crafted JSON breaks the ordering the merge depends on) decodes as
    /// the oldest possible timestamp. See CODE_AUDIT_15 §5.3.
    ///
    /// The decoded clock is otherwise stored unchanged — it used to also be capped at "now
    /// plus the allowed skew" here, but "now" is decode time, not observation time: decoding
    /// the same stored value again later (or on another device, at a different moment)
    /// produced a *different* clamped value, so two far-future writes could tie differently
    /// per replica and replicas would not converge. Skew clamping now happens only once, when
    /// the timestamp is actually observed into the local hybrid clock (`MonotonicWallClock
    /// .observe(_:)`, called from the CRDT merge path), not on every decode. See
    /// CODE_AUDIT_17 §5.15.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedClock = try container.decode(TimeInterval.self, forKey: .clock)
        clock = decodedClock.isFinite ? decodedClock : 0
        actorId = try container.decode(ActorID.self, forKey: .actorId)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clock, forKey: .clock)
        try container.encode(actorId, forKey: .actorId)
    }
}

extension WallclockTimestamp: Sendable where ActorID: Sendable {}

extension WallclockTimestamp: Equatable {}

extension WallclockTimestamp: Hashable {}

extension WallclockTimestamp: PartiallyOrderable {}

extension WallclockTimestamp: CustomStringConvertible {
    /// The description of the timestamp.
    ///
    /// In the format `[clockValue-actorID]`.
    public var description: String {
        "[\(clock)-\(actorId)]"
    }
}

extension WallclockTimestamp: CustomDebugStringConvertible {
    /// The debug description of the timestamp.
    public var debugDescription: String {
        "LamportTimestamp<\(clock), \(actorId)>"
    }
}

#if DEBUG
    extension WallclockTimestamp: ApproxSizeable {
        public func sizeInBytes() -> Int {
            MemoryLayout<TimeInterval>.size(ofValue: clock) + MemoryLayout<ActorID>.size(ofValue: actorId)
        }
    }
#endif
