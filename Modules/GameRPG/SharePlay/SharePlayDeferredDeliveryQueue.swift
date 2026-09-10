// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Shared retry-until-removed loop

/// Retries `remove` on `delays`' schedule (repeating the last delay once
/// exhausted) until it returns `true`, `Task` cancellation is observed, or
/// `isObsolete` (when provided) reports true — then calls `finish()` exactly
/// once. `isObsolete` is re-checked both before and after each `remove` call
/// so a mid-attempt transition to obsolete is caught immediately rather than
/// waiting out a full backoff cycle first.
///
/// Shared by the 3 best-effort attachment-cleanup retry loops across this
/// file and `SharePlayJournalPublicationQueue.swift` (removal after a
/// cancelled add, an emergency cleanup, and a timed-out add's post-cleanup) —
/// previously each hand-rolled the same ~15-line skeleton. See CODE_AUDIT §9.6.
@MainActor
func retryUntilRemoved(
    delays: [Duration],
    isObsolete: (() -> Bool)? = nil,
    sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    remove: () async -> Bool,
    finish: () -> Void
) async {
    var retryIndex = 0
    while !Task.isCancelled {
        if let isObsolete, isObsolete() {
            _ = await remove()
            break
        }
        if await remove() {
            break
        }
        if let isObsolete, isObsolete() {
            _ = await remove()
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
    nonisolated static let metadataHeadroom = 1_000_000
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

    private enum Key: Hashable, Sendable {
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
        case event(
            sessionId: UUID,
            participantId: UUID?,
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
        if Self.isRepair(key) || Self.isEvent(key) {
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

        if model.isFileBackedPresentation || model.isPlayerFilePresentationEvent {
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

    /// Shared by the 3 best-effort attachment-cleanup retry loops across this
    /// module — previously the same 4-element literal was hand-copied at each
    /// site. See CODE_AUDIT §9.4.
    static let cleanupRetryDelays: [Duration] = [
        .milliseconds(250),
        .seconds(1),
        .seconds(2),
        .seconds(5)
    ]

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
