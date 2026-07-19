// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

@MainActor @Observable
final class LogGameModel: Identifiable {
    init(
        id: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        module: NetworkModules,
        itemId: UUID,
        players: [UUID] = [],
        sharePlayTransport: SharePlayTransportLog = SharePlayTransportLog()
    ) {
        self.id = id
        self.type = type
        self.subType = subType
        self.module = module
        self.itemId = itemId
        self.players = players
        self.sharePlayTransport = sharePlayTransport
    }
    
    var id: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var module: NetworkModules
    var itemId: UUID
    var players: [UUID] = []
    var sharePlayTransport: SharePlayTransportLog
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
