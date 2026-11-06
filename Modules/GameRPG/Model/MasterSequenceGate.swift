// @copyright André Trettin

import Foundation

/// Orders the game master's changes of one kind: a change counts only if it is newer than the
/// last accepted one of the same session. A new session (a master restart) starts a new order.
struct MasterSequenceGate: Equatable, Sendable {
    private var last: (sessionId: UUID, sequence: Int)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.last?.sessionId == rhs.last?.sessionId && lhs.last?.sequence == rhs.last?.sequence
    }

    /// Accepts a change and remembers it, or returns `false` for a replay or a late copy.
    mutating func accept(sessionId: UUID, sequence: Int) -> Bool {
        if let last, last.sessionId == sessionId, sequence <= last.sequence { return false }
        last = (sessionId, sequence)
        return true
    }

    /// Forgets the order: a lost connection or the end of the game.
    mutating func reset() {
        last = nil
    }
}

/// The game master's counters, one per kind of ordered change.
struct MasterSequenceSource: Sendable {
    enum Kind: Hashable, Sendable {
        case mapPhoto
        case tableWeather
    }

    private var counters: [Kind: Int] = [:]

    /// The sequence of the master's next change of `kind`.
    mutating func next(_ kind: Kind) -> Int {
        let value = (counters[kind] ?? 0) + 1
        counters[kind] = value
        return value
    }
}
