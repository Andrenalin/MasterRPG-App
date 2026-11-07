// @copyright André Trettin

import CoreRPG
import Foundation

/// Orders the availability lists (`audioList`, `photoList`, `pdfList`, `spaceList`) of a game: a
/// list is applied only when its counter is newer than the last one applied from the same sender
/// for the same module, so a list that arrives late cannot overwrite a newer one.
///
/// One tracker per controller model replaces what was a dictionary and three methods per module.
/// Counter 0 is accepted without being recorded (a message without a counter). See
/// CODE_AUDIT_Audio2 §9.3.
struct ListSequenceTracker: Sendable {
    private var lastCounters: [NetworkModules: [UUID: Int]] = [:]

    /// Whether a list of `module` from `senderId` with `counter` is newer than the last one.
    func canApply(_ module: NetworkModules, from senderId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastCounters[module]?[senderId] ?? 0)
    }

    /// Remembers an applied list.
    mutating func record(_ module: NetworkModules, counter: Int, from senderId: UUID) {
        guard counter > 0 else { return }
        lastCounters[module, default: [:]][senderId] = counter
    }

    /// Forgets what was kept for a sender that left.
    mutating func forget(senderId: UUID) {
        for module in lastCounters.keys {
            lastCounters[module]?[senderId] = nil
        }
    }

    /// Starts one module over, or every module.
    mutating func reset(_ module: NetworkModules? = nil) {
        if let module {
            lastCounters[module] = nil
        } else {
            lastCounters.removeAll()
        }
    }
}
