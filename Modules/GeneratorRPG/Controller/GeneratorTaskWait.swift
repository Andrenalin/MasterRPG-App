// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import FoundationModels
import SwiftUI
import Synchronization

// The task wait helpers, split out of GeneratorController.swift. See CODE_AUDIT_29 §9.9.

/// Waits for a task to end, but no longer than a timeout. `task.value` alone does not stop waiting
/// when the waiter is cancelled and never returns for a task that ignores its cancellation.
/// Internal so it can be tested. See CODE_AUDIT_26 §10.18.
enum GeneratorTaskWait {
    static let predecessorTimeout: Duration = .seconds(5)

    static func end(of task: Task<Void, Never>, timeout: Duration) async {
        let gate = OneShotGate()
        let timer = Task {
            try? await Task.sleep(for: timeout)
            gate.open()
        }
        let waiter = Task {
            await task.value
            gate.open()
        }
        // A cancelled waiter stops waiting at once instead of after the task or the timeout.
        // See CODE_AUDIT_26 §3.14.
        await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            gate.open()
        }
        // Neither helper outlives the wait. See CODE_AUDIT_29 §3.7.
        timer.cancel()
        waiter.cancel()
    }
}

/// Resumes its one waiter the first time it is opened, also when that is before `wait`.
final class OneShotGate: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Void, Never>)
        case open
    }

    private let state = Mutex<State>(.idle)

    /// Whether a task is suspended in `wait()`. Lets a test open the gate only once its waiter is parked.
    var hasWaiter: Bool {
        state.withLock { state in
            if case .waiting = state { return true }
            return false
        }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isOpen = state.withLock { state -> Bool in
                if case .open = state { return true }
                state = .waiting(continuation)
                return false
            }
            if isOpen { continuation.resume() }
        }
    }

    func open() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            defer { state = .open }
            if case let .waiting(continuation) = state { return continuation }
            return nil
        }
        continuation?.resume()
    }
}

#endif
