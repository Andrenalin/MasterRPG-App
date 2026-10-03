//
//  LWWRegister.swift
//
// Based on code written by Drew McCormack on 29/04/2020.
// Used under MIT License
// Source: https://github.com/appdecentral/replicatingtypes/blob/master/Sources/ReplicatingTypes/ReplicatingRegister.swift

import Foundation

/// An actor id a register stamps its local writes with, distinct on every device.
///
/// The id a register is created with is stored in it and decoded on every device, so all
/// replicas would write with the same actor and two devices writing the same clock tick
/// would tie, swap values on merge and never converge. See CODE_AUDIT_20 §5.8.
public protocol LWWActorID: Hashable, Comparable {
    /// The identity of this install.
    static var local: Self { get }
}

extension String: LWWActorID {
    public static var local: String { LocalActorId.value }
}

/// A random id created once per install and kept in `UserDefaults`.
private enum LocalActorId {
    static let value: String = {
        let key = BundleIds.app("crdtLocalActorId")
        if let stored = UserDefaults.standard.string(forKey: key), !stored.isEmpty {
            return stored
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()
}

/// A Last-Writer-Wins Register.
///
/// The `LWWRegister` implementation is based on an optimized CRDT register type as described in
/// [A comprehensive study of Convergent and Commutative Replicated Data Types](https://hal.inria.fr/inria-00555588/document)”
/// by Marc Shapiro, Nuno Preguiça, Carlos Baquero, and Marek Zawirski (2011).
public struct LWWRegister<ActorID: LWWActorID, T> {
    /// A struct that represents the state of an LWWRegister
    public struct Metadata {
        internal var value: T
        internal var clockId: WallclockTimestamp<ActorID>

        // See MonotonicWallClock's doc comment — the default here (not
        // WallclockTimestamp's own, unused when called from here since this
        // always passes `timestamp` through explicitly) is what every local
        // `LWWRegister.value =` assignment actually goes through.
        init(value: T, id: ActorID, timestamp: TimeInterval = MonotonicWallClock.now()) {
            self.value = value
            clockId = WallclockTimestamp(actorId: id, timestamp: timestamp)
        }

        // MARK: Conformance of LWWRegister.Atom to PartiallyOrderable

        /// Returns a Boolean value that indicates if the atom is less-than or equal to another atom.
        /// - Parameters:
        ///   - lhs: The first atom to compare.
        ///   - rhs: The second atom to compare.
        public static func <= (lhs: Self, rhs: Self) -> Bool {
            // functionally equivalent to say rhs instance is ordered after lhs instance
            lhs.clockId <= rhs.clockId
        }
    }

    private var _storage: Metadata
    internal let selfId: ActorID

    /// The value of the register.
    public var value: T {
        get {
            _storage.value
        }
        set {
            // A local write overwrites what this replica currently holds, so it must order
            // after it even when the stored clock came from another device (or a previous
            // launch) and is ahead of this device's clock — however far ahead: a stored
            // far-future clock can then never freeze the field. `observe` still bounds how far
            // the process clock itself jumps. See CODE_AUDIT_18 §5.5, CODE_AUDIT_19 §5.5.
            let stored = _storage.clockId.clock
            MonotonicWallClock.observe(stored)
            let afterStored = stored.nextUp.isFinite ? stored.nextUp : stored
            _storage = Metadata(value: newValue, id: ActorID.local, timestamp: max(MonotonicWallClock.now(), afterStored))
        }
    }

    /// Creates a new last-write-wins register.
    /// - Parameters:
    ///   - value: The initial register value.
    ///   - actorID: The identity of the collaborator for this register..
    ///   - timestamp: An optional wall clock timestamp for this register.
    public init(_ value: T, actorID: ActorID, timestamp: TimeInterval? = nil) {
        selfId = actorID
        if let timestamp = timestamp {
            _storage = Metadata(value: value, id: selfId, timestamp: timestamp)
        } else {
            _storage = Metadata(value: value, id: selfId)
        }
    }
}

extension LWWRegister: Replicable {
    public mutating func merging(with other: LWWRegister<ActorID, T>) {
        _storage = Self.mergedStorage(_storage, other._storage)
    }

    /// Returns a new counter by merging two counter instances.
    /// - Parameter other: The counter to merge.
    public func merged(with other: LWWRegister) -> LWWRegister {
        var result = self
        result._storage = Self.mergedStorage(_storage, other._storage)
        return result
    }

    /// Plain last-writer-wins on (clock, actor id): the result depends only on the two atoms,
    /// never on the merging device's time, so every replica converges on the same value.
    ///
    /// Rejecting atoms beyond "now plus the allowed skew" (CODE_AUDIT_18 §5.5) depended on
    /// each replica's local time: a device whose clock ran fast had its edits refused by the
    /// others while keeping them itself, and a re-sent stale atom won once real time caught
    /// up. Freezing is prevented on the write side instead: a local write always orders
    /// after the value it overwrites (`value`'s setter). See CODE_AUDIT_19 §5.5.
    static func mergedStorage(_ local: Metadata, _ remote: Metadata) -> Metadata {
        MonotonicWallClock.observe(remote.clockId.clock)
        return local <= remote ? remote : local
    }
}

extension LWWRegister: Codable where T: Codable, ActorID: Codable {}
extension LWWRegister.Metadata: Codable where T: Codable, ActorID: Codable {}

extension LWWRegister: Sendable where T: Sendable, ActorID: Sendable {}
extension LWWRegister.Metadata: Sendable where T: Sendable, ActorID: Sendable {}

extension LWWRegister: Equatable where T: Equatable {}
extension LWWRegister.Metadata: Equatable where T: Equatable {}

extension LWWRegister: Hashable where T: Hashable {}
extension LWWRegister.Metadata: Hashable where T: Hashable {}
