// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Shared retry-until-removed loop

/// Retries `remove` on `delays`' schedule (repeating the last delay once
/// exhausted) until it returns `true`, `Task` cancellation is observed,
/// `isObsolete` (when provided) reports true, or `maximumAttempts` removals
/// have failed — then calls `finish()` exactly once. `isObsolete` is
/// re-checked both before and after each `remove` call so a mid-attempt
/// transition to obsolete is caught immediately rather than waiting out a
/// full backoff cycle first.
///
/// After `maximumAttempts` the attachment is abandoned and logged as such: a
/// removal that fails for good used to be retried every 5 s for the whole
/// session, holding its cleanup reservation, and eight of those rejected
/// every further Journal publication. See CODE_AUDIT_21 §3.11.
///
/// Shared by the 3 best-effort attachment-cleanup retry loops across this
/// file and `SharePlayJournalPublicationQueue.swift` (removal after a
/// cancelled add, an emergency cleanup, and a timed-out add's post-cleanup) —
/// previously each hand-rolled the same ~15-line skeleton. See CODE_AUDIT §9.6.
@MainActor
func retryUntilRemoved(
    delays: [Duration],
    maximumAttempts: Int = SharePlayAttachmentLoadRetry.maximumCleanupAttempts,
    isObsolete: (() -> Bool)? = nil,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    remove: () async -> Bool,
    finish: () -> Void
) async {
    var retryIndex = 0
    var attempts = 0
    while !Task.isCancelled {
        if let isObsolete, isObsolete() {
            _ = await remove()
            break
        }
        if await remove() {
            break
        }
        attempts += 1
        if let isObsolete, isObsolete() {
            _ = await remove()
            break
        }
        guard attempts < maximumAttempts else {
            Logger.sharePlay.error("Journal: abandoned an attachment cleanup after \(attempts, privacy: .public) failed removals")
            break
        }
        do {
            try await sleep(delays[retryIndex])
        } catch {
            break
        }
        retryIndex = min(retryIndex + 1, delays.count - 1)
    }
    finish()
}

// MARK: - Attachment load retry

/// Retries the transient window where a journal entry is visible before its
/// CloudAsset upload is downloadable by another participant.
enum SharePlayAttachmentLoadRetry {
    static let defaultRetryDelays = GameLimits.SharePlay.attachmentRetryDelays

    /// While a large upload is still in progress every load throws. The outer deadline of the
    /// load (30-180 s) and `isStillWanted` end the waiting, so these delays only space the
    /// attempts: a short back-off first, then one try every few seconds. See
    /// CODE_AUDIT_Game_Shareplay §5.13.
    static let uploadWaitDelays = GameLimits.SharePlay.uploadWaitDelays

    /// `load` for an attachment whose upload may still be running: it keeps trying until the
    /// caller's deadline or cancellation stops it.
    static func loadWhileUploading<Value: Sendable>(
        sleep: @Sendable (Duration) async throws -> Void = { delay in
            try await Task.sleep(for: delay)
        },
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await load(retryDelays: uploadWaitDelays, sleep: sleep, operation: operation)
    }

    /// Shared by the best-effort attachment-cleanup retry loops.
    static let cleanupRetryDelays = GameLimits.SharePlay.cleanupRetryDelays

    /// Removals a cleanup loop tries before it abandons the attachment and frees its
    /// reservation. Each one is itself a bounded `load` retry, so this is a few minutes of a
    /// Journal that keeps refusing the removal. See CODE_AUDIT_21 §3.11.
    static let maximumCleanupAttempts = 24

    static func load<Value: Sendable>(
        retryDelays: [Duration] = defaultRetryDelays,
        sleep: @Sendable (Duration) async throws -> Void = { delay in
            try await Task.sleep(for: delay)
        },
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        for delay in retryDelays {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try await sleep(delay)
            }
        }

        try Task.checkCancellation()
        return try await operation()
    }
}

// MARK: - Attachment load deadline

/// Why a bounded Journal attachment load stopped before it produced data.
enum SharePlayAttachmentLoadAbort: Error, Equatable, Sendable {
    /// The load neither returned nor threw within its deadline.
    case deadlineExceeded
    /// The attachment disappeared from the live Journal snapshot while loading.
    case noLongerCurrent
}

extension SharePlayAttachmentLoadRetry {
    /// `GroupSessionJournal.Attachment.load` can stay suspended forever when the master removes
    /// a replaced attachment (or its CloudAsset never finishes uploading) while a player is still
    /// loading it. The Journal consumer is sequential, so one such load froze every later
    /// publication on that player: the photo then appeared only after the system gave up.
    ///
    /// Races `operation` against `deadline` and against `isStillWanted` (polled every
    /// `pollInterval`). The first outcome wins and the losers are cancelled. The result does not
    /// depend on `operation` honouring cancellation, so a load that never returns still ends.
    static func load<Value: Sendable>(
        deadline: Duration,
        pollInterval: Duration = .milliseconds(500),
        isStillWanted: @escaping @Sendable () async -> Bool = { true },
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = SharePlayAttachmentLoadRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let work = Task {
                    do {
                        race.finish(.success(try await operation()))
                    } catch {
                        race.finish(.failure(error))
                    }
                }
                let watchdog = Task {
                    let clock = ContinuousClock()
                    let end = clock.now.advanced(by: deadline)
                    while !Task.isCancelled {
                        // Checked before the first sleep: an attachment the master already
                        // replaced is not worth even starting a multi-MB download for.
                        if await !isStillWanted() {
                            race.finish(.failure(SharePlayAttachmentLoadAbort.noLongerCurrent))
                            return
                        }
                        let remaining = clock.now.duration(to: end)
                        guard remaining > .zero else {
                            race.finish(.failure(SharePlayAttachmentLoadAbort.deadlineExceeded))
                            return
                        }
                        do {
                            try await Task.sleep(for: min(pollInterval, remaining))
                        } catch {
                            return
                        }
                    }
                }
                race.adopt([work, watchdog])
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

/// First-result-wins gate: resumes the caller exactly once and cancels the other racers.
private final class SharePlayAttachmentLoadRace<Value: Sendable>: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, any Error>?
        var pending: Result<Value, any Error>?
        var finished = false
        var tasks: [Task<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let pending = state.withLock { state -> Result<Value, any Error>? in
            if let pending = state.pending { return pending }
            state.continuation = continuation
            return nil
        }
        if let pending { continuation.resume(with: pending) }
    }

    /// Registers the racers; they are cancelled at once when the race has already ended.
    func adopt(_ tasks: [Task<Void, Never>]) {
        let alreadyFinished = state.withLock { state -> Bool in
            if state.finished { return true }
            state.tasks = tasks
            return false
        }
        if alreadyFinished { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<Value, any Error>) {
        let (continuation, tasks) = state.withLock { state -> (CheckedContinuation<Value, any Error>?, [Task<Void, Never>]) in
            guard !state.finished else { return (nil, []) }
            state.finished = true
            defer { state.continuation = nil; state.tasks = [] }
            if state.continuation == nil { state.pending = result }
            return (state.continuation, state.tasks)
        }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
