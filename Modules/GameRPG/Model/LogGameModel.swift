// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// Stable identity for one master-originated message.
///
/// Message counters restart for every game. Pairing the counter with a fresh
/// game-session identifier prevents a delayed acknowledgement from a previous
/// game from completing a row in the current game.
struct GameDeliveryMessageId: Hashable, Codable, Sendable {
    init(sessionId: UUID, counter: Int) {
        self.sessionId = sessionId
        self.counter = counter
    }

    let sessionId: UUID
    let counter: Int

    static let legacySessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// The archived and sent keys keep their `ID` spelling; the properties follow the
    /// project's `Id` casing. See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case sessionId = "sessionID"
        case counter
    }
}

/// The recipient as it was known when the master sent the message.
///
/// Keeping the name in the snapshot means a later leave, rename, or join does
/// not rewrite the history shown by the delivery log.
struct LogMessageRecipient: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

@MainActor @Observable
final class LogGameModel: Identifiable {
    init(
        id: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        module: NetworkModules,
        itemId: UUID,
        players: [UUID] = [],
        messageId: GameDeliveryMessageId? = nil,
        expectedRecipients: [LogMessageRecipient] = [],
        tracksDelivery: Bool? = nil,
        sharePlayTransport: SharePlayTransportLog = SharePlayTransportLog(),
        note: String? = nil
    ) {
        self.id = id
        self.note = note
        self.messageId = messageId ?? GameDeliveryMessageId(
            sessionId: GameDeliveryMessageId.legacySessionId,
            counter: id
        )
        self.type = type
        self.subType = subType
        self.module = module
        self.itemId = itemId
        self.expectedRecipients = expectedRecipients
        self.tracksDelivery = tracksDelivery ?? (type == .reveal)
        var uniquePlayers = Set<UUID>()
        self.receivedPlayerOrder = players.filter { uniquePlayers.insert($0).inserted }
        self.receivedPlayerIds = uniquePlayers
        self.sharePlayTransport = sharePlayTransport
    }
    
    let id: Int
    /// A line of text shown in place of the message description: the row is a notice for the
    /// person at this device, not a sent message. See CODE_AUDIT_21 §5.5.
    let note: String?
    let messageId: GameDeliveryMessageId
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var module: NetworkModules
    var itemId: UUID
    let expectedRecipients: [LogMessageRecipient]
    let tracksDelivery: Bool
    private var receivedPlayerIds: Set<UUID>
    private var receivedPlayerOrder: [UUID]

    /// Compatibility view for existing log UI and previews. Assigning the
    /// array is intentionally lossless only with respect to unique player IDs.
    var players: [UUID] {
        get {
            receivedPlayerOrder
        }
        set {
            var uniquePlayers = Set<UUID>()
            receivedPlayerOrder = newValue.filter { uniquePlayers.insert($0).inserted }
            receivedPlayerIds = uniquePlayers
        }
    }

    var sharePlayTransport: SharePlayTransportLog

    @discardableResult
    func acknowledge(playerId: UUID) -> Bool {
        guard expectedRecipients.contains(where: { $0.id == playerId }) else { return false }
        guard receivedPlayerIds.insert(playerId).inserted else { return false }
        receivedPlayerOrder.append(playerId)
        return true
    }

    func hasAcknowledgement(from playerId: UUID) -> Bool {
        receivedPlayerIds.contains(playerId)
    }
}

enum SharePlayJournalTransportState: Equatable, Sendable {
    case pending
    case succeeded
    case failed
}

struct SharePlayJournalTransportLog: Equatable, Sendable {
    let byteCount: Int
    var state: SharePlayJournalTransportState
}

enum SharePlayChunkTransportState: Equatable, Sendable {
    case pending
    case succeeded
    case failed
}

struct SharePlayChunkTransportLog: Equatable, Sendable {
    let count: Int
    let byteCount: Int
    var state: SharePlayChunkTransportState = .pending
}

struct SharePlayTransportLog: Equatable, Sendable {
    var journal: SharePlayJournalTransportLog?
    var chunked: SharePlayChunkTransportLog?

    var isEmpty: Bool {
        journal == nil && chunked == nil
    }
}
