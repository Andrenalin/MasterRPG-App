// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

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
        /// The answer to a participant's request for an audio or weather item. It is kept per
        /// recipient, item and version, and nothing replaces it but a newer attempt of itself.
        case answer(
            sessionId: UUID,
            participantId: UUID?,
            targetId: UUID,
            module: NetworkModules,
            itemId: UUID,
            assetVersion: Int
        )
        /// An ordinary game-state message (dice roll, value or health update, table change,
        /// map pin) that is neither a targeted answer nor a file-backed presentation. It does
        /// not coalesce: an earlier dice roll is not superseded by a later unrelated one, so
        /// each message keeps its own slot, told apart by its outgoing `counter`. The sender is
        /// part of the key because the master relays LAN players' messages with the players'
        /// own counters, which all start at 1.
        case event(
            sessionId: UUID,
            participantId: UUID?,
            senderId: UUID,
            module: NetworkModules,
            counter: Int
        )
    }

    /// `maxCount` is larger than the file retries alone would need: ordinary game-state events
    /// (see `.event`) are far more frequent during active play, and a busy combat round can
    /// produce many dice rolls and value updates in quick succession. Event payloads are tiny,
    /// so the byte budget is unaffected.
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
    /// physical recipient. Targeted Audio/Weather answers retain an exact
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
        // older intent, so it must not coalesce over the newer entry. Answers
        // keep their exact-key replacement and priority because they answer an
        // explicit participant request.
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

        // Answers answer an explicit participant request, and events are
        // discrete occurrences that must not be silently dropped either
        // (see `.event`'s doc comment). An answer may displace coalescible
        // presentation intent under pressure, never another answer or event.
        //
        // An event is not allowed to: a presentation is the game master's latest word for a
        // module, and coalescing keeps only one per module, so dropping it loses what the
        // players see for good while an event is one of many. The event is refused instead.
        // See CODE_AUDIT_Game_Shareplay §5.12.
        if Self.isAnswer(key) {
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
        if Self.isAnswer(key) {
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
            return .answer(
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
        return .event(
            sessionId: sessionId,
            participantId: participantId,
            senderId: model.sender.id,
            module: model.data.type,
            counter: model.counter
        )
    }

    private static func isAnswer(_ key: Key) -> Bool {
        if case .answer = key { return true }
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
