// @copyright André Trettin

import CoreRPG
import Foundation
import Network

@testable import GameRPG

final class MasterNetworkStoreDelegateMock: MasterNetworkStoreDelegate, @unchecked Sendable {
    var acceptsMessages = true
    var acceptedOrigins: [GameMessageOrigin] = []
    var calledLostPlayer = 0
    var calledReady = 0
    var readyOrigins: [GameMessageOrigin] = []
    var calledReceived = 0
    var calledFileReceived = 0
    var receivedHandler: ((GameNetworkModel, GameMessageOrigin) -> Void)?
    var receivedFileHandler: ((GameNetworkModel) -> Void)?

    func accepts(_ model: GameNetworkModel, origin: GameMessageOrigin) -> Bool {
        acceptedOrigins.append(origin)
        return acceptsMessages
    }
    
    func lostPlayer(for connectionId: ConnectionController.ID) {
        calledLostPlayer += 1
    }
    
    func ready(for origin: GameMessageOrigin) {
        calledReady += 1
        readyOrigins.append(origin)
    }
    
    func received(_ model: GameNetworkModel, origin: GameMessageOrigin) {
        calledReceived += 1
        receivedHandler?(model, origin)
    }
    
    func receivedFile(_ model: GameNetworkModel) {
        calledFileReceived += 1
        receivedFileHandler?(model)
    }

}

final class PlayerNetworkStoreDelegateMock: PlayerNetworkStoreDelegate, @unchecked Sendable {

    var pinnedSharePlayMasterParticipantID: UUID?
    var acceptsSharePlayPeerMessageHandler: ((GameNetworkModel, UUID) -> Bool)?
    var shouldDeferSharePlayPeerGroupEventHandler: ((GameNetworkModel, UUID) -> Bool)?
    var didAcceptSharePlayMasterStateHandler: ((GameNetworkModel, UUID) -> Bool)?
    var receivedSharePlayHandler: ((GameNetworkModel, UUID) -> Void)?
    var receivedSharePlayHistory: [GameNetworkModel] = []
    /// `nil` preserves the permissive default used by legacy unit tests. An
    /// explicit array opts a test into the production roster gate.
    var authoritativeSharePlayRoster: [PlayerGameModel]?
    private var acceptedSharePlayMasterID: UUID?
    private var acceptedSharePlayMasterStateCounter: Int?
    var calledLostConnection = 0
    var calledReady = 0
    var calledReceived = 0
    var calledFileReceived = 0
    var calledFileLoadFailed = 0
    var calledMasterJournalAdmission = 0

    func lostConnection() {
        calledLostConnection += 1
    }

    func ready() {
        calledReady += 1
    }

    func received(_: GameNetworkModel) {
        calledReceived += 1
    }

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) {
        calledReceived += 1
        receivedSharePlayHistory.append(model)
        if authoritativeSharePlayRoster != nil,
           let masterState = model.masterState,
           model.sender.isMaster,
           model.sender.id == model.masterId {
            authoritativeSharePlayRoster = masterState.players
            acceptedSharePlayMasterID = model.masterId
            acceptedSharePlayMasterStateCounter = model.counter
            pinnedSharePlayMasterParticipantID = participantId
        }
        receivedSharePlayHandler?(model, participantId)
    }

    func receivedFile(_ model: GameNetworkModel) {
        calledFileReceived += 1
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) {
        calledFileLoadFailed += 1
    }

    func isPinnedSharePlayMasterParticipant(id: UUID) -> Bool {
        pinnedSharePlayMasterParticipantID == id
    }

    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) -> Bool {
        if let handler = acceptsSharePlayPeerMessageHandler {
            return handler(model, participantId)
        }
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return false }
        guard let authoritativeSharePlayRoster else { return true }
        return authoritativeSharePlayRoster.contains {
            $0.id == model.sender.id && $0.type == .player
        }
    }

    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) -> Bool {
        if let handler = shouldDeferSharePlayPeerGroupEventHandler {
            return handler(model, participantId)
        }
        guard model.isDeferrablePlayerGroupEvent,
              let authoritativeSharePlayRoster
        else { return false }
        return !authoritativeSharePlayRoster.contains {
            $0.id == model.sender.id
        }
    }

    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) -> Bool {
        if let handler = didAcceptSharePlayMasterStateHandler {
            return handler(model, participantId)
        }
        return pinnedSharePlayMasterParticipantID == participantId &&
            acceptedSharePlayMasterID == model.masterId &&
            acceptedSharePlayMasterStateCounter == model.counter &&
            model.masterState != nil
    }

    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) -> Bool {
        calledMasterJournalAdmission += 1
        guard model.isMasterJournalAdmissionMetadata,
              model.sender.id == model.masterId,
              model.masterState != nil
        else { return false }
        pinnedSharePlayMasterParticipantID = participantId
        return true
    }
}
