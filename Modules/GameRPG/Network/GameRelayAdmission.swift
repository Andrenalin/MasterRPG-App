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
    private var order: [GameRelayAdmissionKey] = []
    private var keys: Set<GameRelayAdmissionKey> = []

    init(limit: Int = 512) {
        self.limit = limit
    }

    func admit(_ model: GameNetworkModel) -> Bool {
        guard let messageID = model.messageID else {
            // V1 has no stable message identity. Its controller-side pipeline
            // still deduplicates positive counters; do not guess for counter zero.
            return true
        }
        let key = GameRelayAdmissionKey(
            senderID: model.sender.id,
            messageID: messageID,
            hasData: model.data.data != nil
        )
        guard keys.insert(key).inserted else { return false }
        order.append(key)
        while order.count > limit {
            keys.remove(order.removeFirst())
        }
        return true
    }

    func reset() {
        order.removeAll()
        keys.removeAll()
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
        maximumEventByteCount: Int = 64 * 1_024,
        maximumTotalByteCount: Int = 512 * 1_024
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
