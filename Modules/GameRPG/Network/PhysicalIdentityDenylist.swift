// @copyright André Trettin

import Foundation

/// A bounded, FIFO-evicted set of identities that have been explicitly
/// retired — shared by every place in the reconnect path that needs to
/// remember "this physical identity already departed, so a late-arriving
/// claim to rebind under it must not be trusted."
///
/// A redelivery that arrives after the real departure must not be mistaken for a fresh rebind:
/// it would squat the slot a genuine reconnect needs. This type is the one place that invariant
/// is implemented, for the LAN connection ids and the SharePlay master participant alike: the
/// memory is bounded, identities are inserted on departure and consulted before a bind is
/// trusted.
struct PhysicalIdentityDenylist<ID: Hashable & Sendable>: Sendable {
    private var denylisted: Set<ID> = []
    private var order: [ID] = []
    private let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    func contains(_ id: ID) -> Bool {
        denylisted.contains(id)
    }

    /// Marks `id` as departed. A later `contains(_:)` check returns `true`
    /// until the identity ages out of the bounded window.
    mutating func insert(_ id: ID) {
        guard denylisted.insert(id).inserted else { return }
        order.append(id)
        while order.count > capacity {
            let oldest = order.removeFirst()
            denylisted.remove(oldest)
        }
    }

    /// Lifts a denylisting — used only when the OS itself confirms the same
    /// identity is legitimately active again (e.g. `reinstateConnection`'s
    /// SharePlay-participant-rejoin case), never from a claim carried inside
    /// message content.
    mutating func remove(_ id: ID) {
        guard denylisted.remove(id) != nil else { return }
        order.removeAll { $0 == id }
    }

    mutating func removeAll() {
        denylisted.removeAll()
        order.removeAll()
    }
}
