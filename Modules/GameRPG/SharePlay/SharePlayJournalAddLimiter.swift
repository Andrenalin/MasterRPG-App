// @copyright André Trettin

import Foundation

// MARK: - Add outcome

enum SharePlayJournalAddOutcome<Value: Sendable>: Sendable {
    case succeeded(Value)
    case failed(String)
    case timedOut
    case unavailable
    case cancelled
}

// MARK: - Add attempt limiter

@MainActor
private final class SharePlayJournalAddAttempt<Value: Sendable> {
    var continuation: CheckedContinuation<SharePlayJournalAddOutcome<Value>, Never>?
    var operationTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    var isWaiting = true
    var isCleaningLateValue = false
    var isObsolete = false
}

private struct SharePlayJournalAddAttemptKey<Key: Hashable & Sendable>: Hashable, Sendable {
    let key: Key
    let scope: UUID?
}

/// Bounds a non-cooperative `GroupSessionJournal.add` to one quarantined task
/// per module. A timeout finishes the logical publication immediately, while
/// the underlying task stays retained and blocks another Journal add for that
/// module until it actually returns. A late attachment is removed instead of
/// being committed as current state.
@MainActor
final class SharePlayJournalAddLimiter<Key: Hashable & Sendable, Value: Sendable> {
    init(maxRetainedAttempts: Int = 16, maxObsoleteAttempts: Int = 8) {
        self.maxRetainedAttempts = max(1, maxRetainedAttempts)
        self.maxObsoleteAttempts = max(1, maxObsoleteAttempts)
    }

    /// Cap for the attempts of the current session.
    private let maxRetainedAttempts: Int
    /// Cap for the attempts of ended sessions whose system call has not returned. They are
    /// counted apart: an ended session's hung adds must not use up the Journal of the next
    /// session, yet each one keeps its payload alive, so their number stays bounded.
    private let maxObsoleteAttempts: Int
    private var attempts: [SharePlayJournalAddAttemptKey<Key>: SharePlayJournalAddAttempt<Value>] = [:]

    var activeCount: Int {
        attempts.count
    }

    func run(
        for key: Key,
        scope: UUID? = nil,
        timeout: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        lateCleanupSleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        operation: @escaping @MainActor () async throws -> Value,
        discardLateValue: @escaping @MainActor (Value) async -> Bool
    ) async -> SharePlayJournalAddOutcome<Value> {
        let attemptKey = SharePlayJournalAddAttemptKey(key: key, scope: scope)
        let obsoleteCount = attempts.values.filter(\.isObsolete).count
        guard attempts[attemptKey] == nil,
              attempts.count - obsoleteCount < maxRetainedAttempts,
              obsoleteCount < maxObsoleteAttempts
        else { return .unavailable }

        let attempt = SharePlayJournalAddAttempt<Value>()
        attempts[attemptKey] = attempt

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, attempt.isWaiting else {
                    attempts[attemptKey] = nil
                    continuation.resume(returning: .cancelled)
                    return
                }
                attempt.continuation = continuation
                attempt.operationTask = Task { @MainActor [weak self, weak attempt] in
                    guard let self, let attempt else { return }
                    let result: SharePlayJournalAddOutcome<Value>
                    do {
                        result = .succeeded(try await operation())
                    } catch is CancellationError {
                        result = .cancelled
                    } catch {
                        result = .failed(error.localizedDescription)
                    }
                    await self.operationFinished(
                        result,
                        key: attemptKey,
                        attempt: attempt,
                        lateCleanupSleep: lateCleanupSleep,
                        discardLateValue: discardLateValue
                    )
                }
                attempt.timeoutTask = Task { @MainActor [weak self, weak attempt] in
                    do {
                        try await sleep(timeout)
                    } catch {
                        return
                    }
                    guard let self, let attempt else { return }
                    self.timeout(key: attemptKey, attempt: attempt)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak attempt] in
                guard let self, let attempt else { return }
                self.cancelWaiter(key: attemptKey, attempt: attempt)
            }
        }
    }

    /// Cancels logical waiters on session reset but deliberately retains the
    /// underlying add tasks under `maxRetainedAttempts`. A replacement session
    /// uses a different scope, so one obsolete system call cannot quarantine
    /// that module forever or accumulate untracked orphan work.
    func cancelAll() {
        for (key, attempt) in attempts {
            attempt.isObsolete = true
            if !attempt.isCleaningLateValue {
                attempt.operationTask?.cancel()
            }
            cancelWaiter(key: key, attempt: attempt)
        }
    }

    private func timeout(
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>
    ) {
        guard attempts[key] === attempt, attempt.isWaiting else { return }
        attempt.isWaiting = false
        attempt.timeoutTask = nil
        attempt.operationTask?.cancel()
        let continuation = attempt.continuation
        attempt.continuation = nil
        continuation?.resume(returning: .timedOut)
    }

    private func cancelWaiter(
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>
    ) {
        guard attempts[key] === attempt, attempt.isWaiting else { return }
        attempt.isWaiting = false
        attempt.timeoutTask?.cancel()
        attempt.timeoutTask = nil
        attempt.operationTask?.cancel()
        let continuation = attempt.continuation
        attempt.continuation = nil
        continuation?.resume(returning: .cancelled)
    }

    private func operationFinished(
        _ result: SharePlayJournalAddOutcome<Value>,
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>,
        lateCleanupSleep: @escaping @Sendable (Duration) async throws -> Void,
        discardLateValue: @escaping @MainActor (Value) async -> Bool
    ) async {
        guard attempts[key] === attempt else { return }
        attempt.operationTask = nil

        if attempt.isWaiting {
            attempt.isWaiting = false
            attempt.timeoutTask?.cancel()
            attempt.timeoutTask = nil
            attempts[key] = nil
            let continuation = attempt.continuation
            attempt.continuation = nil
            continuation?.resume(returning: result)
            return
        }

        // The caller already fell back or the session reset. Never install a
        // late attachment as current Journal state.
        if case .succeeded(let value) = result {
            // The add task was cancelled when it timed out. Run cleanup in a
            // fresh unstructured task so inherited cancellation cannot make
            // `journal.remove` fail before it starts. The attempt retains that
            // task, preserving the one-quarantined-operation-per-module bound.
            // The old GroupSession owns a late attachment once `isObsolete`
            // becomes true, and is already invalidated — `retryUntilRemoved`'s
            // own before/after `isObsolete` re-check (rather than only
            // checking once per iteration) is exactly this loop's original
            // double-check, preserved verbatim. See CODE_AUDIT §9.6.
            let cleanupTask = Task { @MainActor in
                await retryUntilRemoved(
                    delays: SharePlayAttachmentLoadRetry.cleanupRetryDelays,
                    isObsolete: { attempt.isObsolete },
                    sleep: lateCleanupSleep,
                    remove: { await discardLateValue(value) },
                    finish: {}
                )
            }
            attempt.isCleaningLateValue = true
            attempt.operationTask = cleanupTask
            await cleanupTask.value
            attempt.operationTask = nil
            attempt.isCleaningLateValue = false
        }
        attempts[key] = nil
    }
}
