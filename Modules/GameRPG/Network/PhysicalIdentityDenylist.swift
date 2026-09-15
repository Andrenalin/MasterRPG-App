// @copyright André Trettin

import Foundation

/// A bounded, FIFO-evicted set of identities that have been explicitly
/// retired — shared by every place in the reconnect path that needs to
/// remember "this physical identity already departed, so a late-arriving
/// claim to rebind under it must not be trusted."
///
/// Before this type existed, the LAN and SharePlay sides of the game each
/// grew their own ad-hoc version of this idea: `MasterControllerModel`
/// tracked retired `ConnectionController.ID`s in an unbounded `Set` (see
/// CODE_AUDIT_Reconnect §7.1), while the SharePlay master-participant pin and
/// `SharePlayPlayerJournalAdmission`'s sender/participant bindings tracked no
/// departed identities at all — leaving both open to a `GroupSessionMessenger`
/// redelivery arriving after the real departure being mistaken for a fresh,
/// legitimate rebind and permanently squatting the slot a genuine reconnect
/// needed (CODE_AUDIT_Reconnect §3.2, §3.3). This type is the one place that
/// invariant is implemented, so every user gets the same bounded-memory
/// guarantee and the same "insert on departure, consult before trusting a
/// bind" contract. See CODE_AUDIT_Reconnect §9.2.
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
