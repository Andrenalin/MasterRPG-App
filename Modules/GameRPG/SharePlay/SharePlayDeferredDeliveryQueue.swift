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

// MARK: - Messenger payload budget

enum SharePlayMessengerPayloadBudget {
    // GameNetworkModel deliberately uses `.withoutEscapingSlashes`, so Data has
    // only Base64's 4/3 expansion. Reserve one MB for the rest of the model so
    // every admitted raw payload fits the sender's 64 MB complete-message limit
    // without first materializing an undeliverable blob.
    nonisolated static let metadataHeadroom = ByteUnit.megabyte
    nonisolated static let maximumRawPayloadByteCount =
        ((SharePlaySingleQueuePackageSender.maxMessageByteCount - metadataHeadroom) / 4) * 3
    nonisolated static let maximumOutstandingRawPayloadByteCount = maximumRawPayloadByteCount * 2

    nonisolated static func accepts(rawPayloadByteCount: Int) -> Bool {
        rawPayloadByteCount >= 0 && rawPayloadByteCount <= maximumRawPayloadByteCount
    }
}

// MARK: - Deferred delivery admission

enum SharePlayDeferredDeliveryAdmission: Equatable, Sendable {
    case enqueued
    case replaced
    case preservedNewerPresentation
    case enqueuedAfterEvictingPresentations(Int)
    case rejectedTooLarge
    case rejectedSaturated

    var isAccepted: Bool {
        switch self {
        case .enqueued, .replaced, .preservedNewerPresentation,
             .enqueuedAfterEvictingPresentations:
            true
        case .rejectedTooLarge, .rejectedSaturated:
            false
        }
    }
}

// MARK: - Deferred delivery queue

struct SharePlayDeferredDeliveryQueue: Sendable {
    struct Entry: Sendable {
        let model: GameNetworkModel
        let sessionId: UUID
        let participantId: UUID?
        let deliveryAttempt: Int
        let retryNotBefore: ContinuousClock.Instant?

        var byteCount: Int {
            model.data.data?.count ?? 0
        }

        func isReady(at instant: ContinuousClock.Instant) -> Bool {
            guard let retryNotBefore else { return true }
            return retryNotBefore <= instant
        }
    }

    fileprivate enum Key: Hashable, Sendable {
        case presentation(
            sessionId: UUID,
            participantId: UUID?,
            module: NetworkModules
        )
        case repair(
            sessionId: UUID,
            participantId: UUID?,
            targetId: UUID,
            module: NetworkModules,
            itemId: UUID,
            assetVersion: Int
        )
        /// An ordinary game-state message (dice roll, value/health update,
        /// table change, map pin, etc.) — anything that is neither a
        /// targeted audio/weather repair nor a file-backed presentation.
        /// Unlike `.presentation`, these do not coalesce to "only the
        /// latest matters": an earlier dice roll or value update is not
        /// superseded by a later unrelated one, so each distinct message
        /// (identified by its own outgoing `counter`) keeps its own slot.
        /// Before this case existed, `key(for:)` returned `nil` for every
        /// message of this shape, so `enqueue` always answered
        /// `.rejectedSaturated` regardless of actual capacity — these
        /// messages had no path into the retry queue at all and were
        /// silently, permanently dropped under send-queue pressure or a
        /// single transient relay failure. See CODE_AUDIT_Network §5.1.
        ///
        /// The sender is part of the key: the master relays LAN players' messages with the
        /// players' own counters, which all start at 1, so two players' dice rolls with equal
        /// counters used to replace each other here. See CODE_AUDIT_21 §5.6.
        case event(
            sessionId: UUID,
            participantId: UUID?,
            senderId: UUID,
            module: NetworkModules,
            counter: Int
        )
    }

    /// `maxCount` is deliberately larger than the historical default of 8:
    /// this queue previously served only occasional file/repair retries,
    /// but now also admits ordinary game-state events (see `.event` above),
    /// which are far more frequent during active play (a busy combat round
    /// can produce many dice rolls / value updates in quick succession).
    /// The byte budget is unaffected — ordinary event payloads are tiny
    /// compared to the file transfers this queue was originally sized for.
    /// See CODE_AUDIT_Network §5.1.
    init(
        maxCount: Int = 32,
        maxBytes: Int = SharePlayMessengerPayloadBudget.maximumOutstandingRawPayloadByteCount,
        maxEntryBytes: Int = SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount
    ) {
        self.maxCount = max(1, maxCount)
        self.maxBytes = max(1, maxBytes)
        self.maxEntryBytes = max(1, maxEntryBytes)
    }

    private let maxCount: Int
    private let maxBytes: Int
    private let maxEntryBytes: Int
    private var order: [Key] = []
    private var entries: [Key: Entry] = [:]
    private(set) var byteCount = 0

    var count: Int {
        entries.count
    }

    var first: Entry? {
        guard let key = order.first else { return nil }
        return entries[key]
    }

    /// Retains control/presentation intent after both primary transports apply
    /// backpressure. Presentations coalesce to the latest per module and
    /// physical recipient. Targeted Audio/Weather repairs retain an exact
    /// recipient/item/version key. Both count and raw payload bytes are capped.
    @discardableResult
    mutating func enqueue(
        _ model: GameNetworkModel,
        sessionId: UUID,
        participantId: UUID?,
        deliveryAttempt: Int = 0,
        retryNotBefore: ContinuousClock.Instant? = nil
    ) -> SharePlayDeferredDeliveryAdmission {
        let key = Self.key(
            for: model,
            sessionId: sessionId,
            participantId: participantId
        )

        let newByteCount = model.data.data?.count ?? 0
        guard newByteCount <= maxEntryBytes else { return .rejectedTooLarge }
        let existingEntry = entries[key]

        // A failed send can retry after a newer presentation for the same
        // module/recipient has already been deferred. The retry represents the
        // older intent, so it must not coalesce over the newer entry. Repairs
        // deliberately keep their existing exact-key replacement and priority
        // semantics because they answer an explicit participant request.
        if deliveryAttempt > 0,
           Self.isPresentation(key),
           existingEntry != nil {
            return .preservedNewerPresentation
        }

        let hadExistingEntry = existingEntry != nil
        let existingByteCount = existingEntry?.byteCount ?? 0
        var prospectiveCount = hadExistingEntry ? entries.count : entries.count + 1
        var prospectiveByteCount = byteCount - existingByteCount + newByteCount
        var evictedPresentationKeys: [Key] = []

        // Repairs answer an explicit participant request, and events are
        // discrete occurrences that must not be silently dropped either
        // (see `.event`'s doc comment) — both may displace coalescible
        // presentation intent under pressure, never another repair/event.
        // See CODE_AUDIT_Network §5.1.
        //
        // An event is not allowed to: a presentation is the game master's latest word for a
        // module, and coalescing keeps only one per module, so dropping it loses what the
        // players see for good while an event is one of many. The event is refused instead.
        // See CODE_AUDIT_Game_Shareplay §5.12.
        if Self.isRepair(key) {
            for candidate in order where
                (prospectiveCount > maxCount || prospectiveByteCount > maxBytes) &&
                candidate != key && Self.isPresentation(candidate) {
                guard let evicted = entries[candidate] else { continue }
                evictedPresentationKeys.append(candidate)
                prospectiveCount -= 1
                prospectiveByteCount -= evicted.byteCount
            }
        }

        guard prospectiveCount <= maxCount,
              prospectiveByteCount <= maxBytes
        else { return .rejectedSaturated }

        if entries[key] != nil {
            remove(key)
        }
        for evictedKey in evictedPresentationKeys {
            remove(evictedKey)
        }
        entries[key] = Entry(
            model: model,
            sessionId: sessionId,
            participantId: participantId,
            deliveryAttempt: max(0, deliveryAttempt),
            retryNotBefore: retryNotBefore
        )
        if Self.isRepair(key) {
            let insertionIndex = order.firstIndex(where: Self.isPresentation) ?? order.endIndex
            order.insert(key, at: insertionIndex)
        } else {
            order.append(key)
        }
        byteCount += newByteCount

        if !evictedPresentationKeys.isEmpty {
            return .enqueuedAfterEvictingPresentations(evictedPresentationKeys.count)
        }
        return hadExistingEntry ? .replaced : .enqueued
    }

    mutating func removeFirst() {
        guard !order.isEmpty else { return }
        remove(order[0])
    }

    /// Names one entry for `remove(_:)`. Entries have no identity of their own: a key stands
    /// for at most one entry at a time.
    struct EntryToken: Sendable {
        fileprivate let key: Key
    }

    /// The earliest entry in queue order that may be sent at `instant`. An entry that waits for
    /// a retry back-off does not hold back the ones behind it, which are ready already.
    /// See CODE_AUDIT_Game_Shareplay §5.17.
    func firstReady(at instant: ContinuousClock.Instant) -> (token: EntryToken, entry: Entry)? {
        for key in order {
            if let entry = entries[key], entry.isReady(at: instant) {
                return (EntryToken(key: key), entry)
            }
        }
        return nil
    }

    mutating func remove(_ token: EntryToken) {
        remove(token.key)
    }

    /// The first moment after `instant` at which an entry that is not ready now becomes ready.
    func earliestRetry(after instant: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        entries.values.compactMap(\.retryNotBefore).filter { $0 > instant }.min()
    }

    /// Drops every entry `isObsolete` names, e.g. those of an ended session.
    mutating func removeEntries(where isObsolete: (Entry) -> Bool) {
        for key in order where entries[key].map(isObsolete) == true {
            remove(key)
        }
    }

    mutating func reset() {
        order = []
        entries = [:]
        byteCount = 0
    }

    private static func key(
        for model: GameNetworkModel,
        sessionId: UUID,
        participantId: UUID?
    ) -> Key {
        if let targetId = model.targetId,
           (model.data.type == .audio || model.data.type == .weather) {
            return .repair(
                sessionId: sessionId,
                participantId: participantId,
                targetId: targetId,
                module: model.data.type,
                itemId: model.data.id,
                assetVersion: model.data.effectiveAssetVersion
            )
        }

        if model.isPresentation {
            return .presentation(
                sessionId: sessionId,
                participantId: participantId,
                module: model.data.type
            )
        }

        // Every other message shape — see `.event`'s doc comment above.
        // See CODE_AUDIT_Network §5.1.
        return .event(
            sessionId: sessionId,
            participantId: participantId,
            senderId: model.sender.id,
            module: model.data.type,
            counter: model.counter
        )
    }

    private static func isRepair(_ key: Key) -> Bool {
        if case .repair = key { return true }
        return false
    }

    private static func isPresentation(_ key: Key) -> Bool {
        if case .presentation = key { return true }
        return false
    }

    private static func isEvent(_ key: Key) -> Bool {
        if case .event = key { return true }
        return false
    }

    private mutating func remove(_ key: Key) {
        order.removeAll { $0 == key }
        if let entry = entries.removeValue(forKey: key) {
            byteCount = max(0, byteCount - entry.byteCount)
        }
    }
}

// MARK: - Attachment load retry

/// Retries the transient window where a journal entry is visible before its
/// CloudAsset upload is downloadable by another participant.
enum SharePlayAttachmentLoadRetry {
    static let defaultRetryDelays: [Duration] = [
        .milliseconds(250),
        .seconds(1),
        .seconds(2)
    ]

    /// While a large upload is still in progress every load throws. The outer deadline of the
    /// load (30-180 s) and `isStillWanted` end the waiting, so these delays only space the
    /// attempts: a short back-off first, then one try every few seconds. See
    /// CODE_AUDIT_Game_Shareplay §5.13.
    static let uploadWaitDelays: [Duration] =
        [.milliseconds(250), .seconds(1), .seconds(2)] + Array(repeating: .seconds(3), count: 60)

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

    /// Shared by the 3 best-effort attachment-cleanup retry loops across this
    /// module — previously the same 4-element literal was hand-copied at each
    /// site. See CODE_AUDIT §9.4.
    static let cleanupRetryDelays: [Duration] = [
        .milliseconds(250),
        .seconds(1),
        .seconds(2),
        .seconds(5)
    ]

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
