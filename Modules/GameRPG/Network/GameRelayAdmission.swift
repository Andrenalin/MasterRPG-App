// @copyright André Trettin

import CoreRPG
import Foundation

// Widened from `private` to file-default (internal) so `GameNetworkController`
// — which owns and drives these two admission/dedup actors but now lives in
// its own file — can still see them. Neither type is referenced outside
// `GameNetworkController.swift`. See CODE_AUDIT §9.10.

struct GameRelayAdmissionKey: Hashable, Sendable {
    let senderID: UUID
    let messageID: UUID
    let hasData: Bool
}

/// Stops transport retries from crossing a LAN/SharePlay bridge repeatedly.
/// Message identity is sender-scoped because independently generated UUIDs are
/// not globally coordinated. Metadata and its later full Journal payload remain
/// distinct admissions.
actor GameRelayAdmission {
    private let limit: Int
    /// `GroupSessionMessenger` can redeliver the same logical message well
    /// after the fact — e.g. following a participant reconnecting after
    /// being briefly unreachable. A purely count-capped window could evict
    /// that message's admission key long before such a legitimately-delayed
    /// retry arrives (during any long, active session with frequent relay
    /// traffic), causing the retry to be treated as new and relayed a
    /// second time. Age-based eviction keeps a key recognized for at least
    /// this long regardless of how much unrelated traffic passed through in
    /// between; `limit` remains a hard memory backstop for a burst that
    /// arrives within the window. See CODE_AUDIT_Network §5.7.
    private let retentionWindow: Duration
    private let clock: ContinuousClock
    private var order: [GameRelayAdmissionKey] = []
    private var keys: Set<GameRelayAdmissionKey> = []
    private var admittedAt: [GameRelayAdmissionKey: ContinuousClock.Instant] = [:]
    /// Bytes relayed per sender inside `byteBudgetWindow`, oldest first. The GM fans each
    /// relayed frame out to every other player, so one sender's traffic is amplified N−1
    /// times; the budget bounds that. See CODE_AUDIT_18 §6.2.
    private var relayedBytes: [UUID: [(at: ContinuousClock.Instant, count: Int)]] = [:]
    static let byteBudgetWindow: Duration = .seconds(60)
    static let byteBudgetPerSender = 512 * ByteUnit.mebibyte

    init(limit: Int = 512, retentionWindow: Duration = .seconds(120), clock: ContinuousClock = ContinuousClock()) {
        self.limit = limit
        self.retentionWindow = retentionWindow
        self.clock = clock
    }

    func admit(_ model: GameNetworkModel) -> Bool {
        guard let messageID = model.messageID else {
            // V1 has no stable message identity. Its controller-side pipeline
            // still deduplicates positive counters; do not guess for counter zero.
            return true
        }
        let now = clock.now
        pruneExpired(before: now)

        let key = GameRelayAdmissionKey(
            senderID: model.sender.id,
            messageID: messageID,
            hasData: model.data.data != nil
        )
        guard keys.insert(key).inserted else { return false }
        order.append(key)
        admittedAt[key] = now
        while order.count > limit {
            let evicted = order.removeFirst()
            keys.remove(evicted)
            admittedAt[evicted] = nil
        }
        return true
    }

    /// `order` is chronological (append-only, evicted from the front), so
    /// this stops at the first still-fresh entry rather than scanning the
    /// whole window.
    private func pruneExpired(before now: ContinuousClock.Instant) {
        while let oldest = order.first,
              let admittedTime = admittedAt[oldest],
              now - admittedTime > retentionWindow {
            order.removeFirst()
            keys.remove(oldest)
            admittedAt[oldest] = nil
        }
    }

    /// Records `count` relayed bytes for `sender`; `false` once the sender exceeded its
    /// budget for the current window (the frame is then not relayed).
    func admitBytes(_ count: Int, from sender: UUID) -> Bool {
        let now = clock.now
        var history = (relayedBytes[sender] ?? []).filter { now - $0.at < Self.byteBudgetWindow }
        let used = history.reduce(0) { $0 + $1.count }
        guard used + count <= Self.byteBudgetPerSender else {
            relayedBytes[sender] = history
            return false
        }
        history.append((now, count))
        relayedBytes[sender] = history
        return true
    }

    func reset() {
        order.removeAll()
        keys.removeAll()
        admittedAt.removeAll()
        relayedBytes.removeAll()
    }
}

struct SharePlayDeferredPeerGroupEvent: Sendable {
    let model: GameNetworkModel
    let participantID: UUID
}

/// Holds a very small amount of peer intent across the one ordering window in
/// which GroupSessionMessenger can surface a new player's event before the
/// master's roster broadcast. The next accepted master-state update drains the
/// entire batch; entries that are still unknown fail closed during revalidation.
actor SharePlayDeferredPeerGroupEvents {
    private enum LogicalIdentity: Hashable, Sendable {
        case current(senderID: UUID, messageID: UUID)
        case legacy(
            senderID: UUID,
            counter: Int,
            type: RPGMessageType,
            subType: RPGMessageActionType,
            itemId: UUID,
            timestampBits: UInt64
        )
    }

    private struct Key: Hashable, Sendable {
        let participantID: UUID
        let identity: LogicalIdentity
    }

    private struct Pending: Sendable {
        let event: SharePlayDeferredPeerGroupEvent
        let retainedByteCount: Int
    }

    private let maximumEventCount: Int
    private let maximumEventByteCount: Int
    private let maximumTotalByteCount: Int
    private var order: [Key] = []
    private var pendingByKey: [Key: Pending] = [:]
    private var totalByteCount = 0

    init(
        maximumEventCount: Int = 32,
        maximumEventByteCount: Int = 64 * ByteUnit.kibibyte,
        maximumTotalByteCount: Int = 512 * ByteUnit.kibibyte
    ) {
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumEventByteCount = max(0, maximumEventByteCount)
        self.maximumTotalByteCount = max(0, maximumTotalByteCount)
    }

    func retain(_ model: GameNetworkModel, participantID: UUID) -> Bool {
        guard model.isDeferrablePlayerGroupEvent else { return false }
        let payloadByteCount = model.data.data?.count ?? 0
        let senderNameByteCount = model.sender.name.utf8.count
        guard payloadByteCount <= maximumEventByteCount,
              senderNameByteCount <= maximumEventByteCount - payloadByteCount
        else { return false }
        let retainedByteCount = payloadByteCount + senderNameByteCount

        let key = Key(
            participantID: participantID,
            identity: Self.logicalIdentity(for: model)
        )
        if pendingByKey[key] != nil {
            // Messenger retries should not consume another slot.
            return true
        }
        guard order.count < maximumEventCount,
              retainedByteCount <= maximumTotalByteCount,
              totalByteCount <= maximumTotalByteCount - retainedByteCount
        else { return false }

        order.append(key)
        pendingByKey[key] = Pending(
            event: SharePlayDeferredPeerGroupEvent(
                model: model,
                participantID: participantID
            ),
            retainedByteCount: retainedByteCount
        )
        totalByteCount += retainedByteCount
        return true
    }

    func drain() -> [SharePlayDeferredPeerGroupEvent] {
        let events = order.compactMap { pendingByKey[$0]?.event }
        reset()
        return events
    }

    func participantLeft(_ participantID: UUID) {
        let removedKeys = order.filter { $0.participantID == participantID }
        for key in removedKeys {
            if let removed = pendingByKey.removeValue(forKey: key) {
                totalByteCount = max(
                    0,
                    totalByteCount - removed.retainedByteCount
                )
            }
        }
        order.removeAll { $0.participantID == participantID }
    }

    func reset() {
        order.removeAll()
        pendingByKey.removeAll()
        totalByteCount = 0
    }

    private static func logicalIdentity(
        for model: GameNetworkModel
    ) -> LogicalIdentity {
        if let messageID = model.messageID {
            return .current(senderID: model.sender.id, messageID: messageID)
        }
        return .legacy(
            senderID: model.sender.id,
            counter: model.counter,
            type: model.type,
            subType: model.subType,
            itemId: model.data.id,
            timestampBits: model.timestamp.bitPattern
        )
    }
}
