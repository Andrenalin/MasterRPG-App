// @copyright André Trettin

import Foundation
import os.log

/// Owns the tasks that link actions start (toggling or sharing a linked item from a text link).
///
/// `toggleTextLink` is synchronous (it returns the new text), so the follow-up work cannot be
/// awaited by it. A bare `Task { }` had no owner: nothing could cancel it when the game ended, and
/// a failure was dropped without a trace. Here every task is kept until it finishes, a failure is
/// logged, and `cancelAll()` stops the rest when a game ends. See CODE_AUDIT_26 §3.9, §3.10,
/// §3.15, §3.16.
@MainActor
public enum LinkActionTasks {
    private static var tasks: [UUID: Task<Void, Never>] = [:]

    /// Starts `operation` on the main actor and keeps its task until it finishes.
    public static func run(_ operation: sending @escaping @MainActor () async throws -> Void) {
        let id = UUID()
        tasks[id] = Task { @MainActor in
            defer { tasks[id] = nil }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch {
                Logger.linkController.error("Link action failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Cancels every link action still running, e.g. when a game ends.
    public static func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// The number of link actions still running.
    static var runningCount: Int { tasks.count }
}
