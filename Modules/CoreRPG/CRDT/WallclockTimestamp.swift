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

extension WallclockTimestamp: Codable where ActorID: Codable {}

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
