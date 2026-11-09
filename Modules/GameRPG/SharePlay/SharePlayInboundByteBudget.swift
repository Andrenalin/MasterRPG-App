// @copyright André Trettin

import CoreRPG
import Foundation

/// Bounds how many bytes of reassembled packages one SharePlay participant has decoded per
/// minute.
///
/// A completed package is turned into one `Data` and JSON-decoded before any check of who sent
/// it and in which role, and nothing limited how often a participant could make every device
/// do that with a 64 MB package. A package over the budget is dropped undecoded.
/// See CODE_AUDIT_21 §6.5.
@MainActor
struct SharePlayInboundByteBudget {
    static let window: Duration = .seconds(60)
    static let bytesPerSender = 512 * ByteUnit.mebibyte

    private var received: [UUID: [(at: ContinuousClock.Instant, count: Int)]] = [:]

    /// Senders that currently have bytes recorded.
    var senderCount: Int { received.count }

    /// Records `count` bytes from `sender`; `false` once the sender is over its budget for the
    /// current window. A sender whose records have all left the window is forgotten, so the
    /// table holds only the senders that sent lately. See CODE_AUDIT_Game_Shareplay §7.5.
    mutating func admit(_ count: Int, from sender: UUID, now: ContinuousClock.Instant = .now) -> Bool {
        prune(now: now)
        var history = received[sender] ?? []
        let used = history.reduce(0) { $0 + $1.count }
        guard used + count <= Self.bytesPerSender else { return false }
        history.append((now, count))
        received[sender] = history
        return true
    }

    private mutating func prune(now: ContinuousClock.Instant) {
        for (sender, history) in received {
            let current = history.filter { now - $0.at < Self.window }
            received[sender] = current.isEmpty ? nil : current
        }
    }

    /// Gives back `count` of the bytes recorded for `sender`, newest records first. A Journal
    /// load reserves the largest size before it starts, because nothing says how large the
    /// attachment is, and returns what the load did not use.
    /// See CODE_AUDIT_Game_Shareplay §6.2.
    mutating func release(_ count: Int, from sender: UUID) {
        guard count > 0, var history = received[sender] else { return }
        var remaining = count
        var index = history.count
        while index > 0, remaining > 0 {
            index -= 1
            let taken = min(history[index].count, remaining)
            history[index].count -= taken
            remaining -= taken
        }
        let remainingHistory = history.filter { $0.count > 0 }
        received[sender] = remainingHistory.isEmpty ? nil : remainingHistory
    }

    mutating func reset() {
        received.removeAll()
    }
}
