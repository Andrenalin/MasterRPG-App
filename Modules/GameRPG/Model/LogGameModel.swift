// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// Stable identity for one master-originated message.
///
/// Message counters restart for every game. Pairing the counter with a fresh
/// game-session identifier prevents a delayed acknowledgement from a previous
/// game from completing a row in the current game.
struct GameDeliveryMessageID: Hashable, Codable, Sendable {
    init(sessionID: UUID, counter: Int) {
        self.sessionID = sessionID
        self.counter = counter
    }

    let sessionID: UUID
    let counter: Int

    static let legacySessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
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
        messageID: GameDeliveryMessageID? = nil,
        expectedRecipients: [LogMessageRecipient] = [],
        tracksDelivery: Bool? = nil,
        sharePlayTransport: SharePlayTransportLog = SharePlayTransportLog()
    ) {
        self.id = id
        self.messageID = messageID ?? GameDeliveryMessageID(
            sessionID: GameDeliveryMessageID.legacySessionID,
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
        self.receivedPlayerIDs = uniquePlayers
        self.sharePlayTransport = sharePlayTransport
    }
    
    let id: Int
    let messageID: GameDeliveryMessageID
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var module: NetworkModules
    var itemId: UUID
    let expectedRecipients: [LogMessageRecipient]
    let tracksDelivery: Bool
    private var receivedPlayerIDs: Set<UUID>
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
            receivedPlayerIDs = uniquePlayers
        }
    }

    var sharePlayTransport: SharePlayTransportLog

    @discardableResult
    func acknowledge(playerID: UUID) -> Bool {
        guard expectedRecipients.contains(where: { $0.id == playerID }) else { return false }
        guard receivedPlayerIDs.insert(playerID).inserted else { return false }
        receivedPlayerOrder.append(playerID)
        return true
    }

    func hasAcknowledgement(from playerID: UUID) -> Bool {
        receivedPlayerIDs.contains(playerID)
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
