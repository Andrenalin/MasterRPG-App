// @copyright André Trettin

import Foundation

/// Runs the work for a key once at a time: a caller that asks while the work for its key is
/// still running waits for that run instead of starting another (for example a multi-MB export
/// that a join, a retry and a prefetch ask for at once).
///
/// Each waiter can leave on its own. When the last waiter has left, the work is cancelled, so a
/// cancelled caller neither waits for the result nor keeps the work running for nobody. A run
/// is forgotten only by its own identity: a finishing or cancelled run never removes the entry
/// of a newer run of the same key, which would let a further caller start a duplicate.
/// See CODE_AUDIT_Game_Shareplay §3.6.
@MainActor
final class SharedWorkCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private struct Run {
        let id = UUID()
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]
    }

    private var runs: [Key: Run] = [:]

    /// Number of runs in progress.
    var activeRunCount: Int {
        runs.count
    }

    func value(
        for key: Key,
        work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let waiterId = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if runs[key] == nil {
                    var run = Run()
                    let runId = run.id
                    run.task = Task { [weak self] in
                        let result: Result<Value, any Error>
                        do {
                            result = .success(try await work())
                        } catch {
                            result = .failure(error)
                        }
                        self?.finish(key: key, runId: runId, result: result)
                    }
                    runs[key] = run
                }
                runs[key]?.waiters[waiterId] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.removeWaiter(waiterId, key: key)
            }
        }
    }

    private func finish(key: Key, runId: UUID, result: Result<Value, any Error>) {
        guard runs[key]?.id == runId, let run = runs.removeValue(forKey: key) else { return }
        for continuation in run.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func removeWaiter(_ waiterId: UUID, key: Key) {
        guard var run = runs[key], let continuation = run.waiters.removeValue(forKey: waiterId) else { return }
        continuation.resume(throwing: CancellationError())
        guard run.waiters.isEmpty else {
            runs[key] = run
            return
        }
        // Nobody waits any more: the work is stopped and the key is free for a new run.
        runs[key] = nil
        run.task?.cancel()
    }
}
