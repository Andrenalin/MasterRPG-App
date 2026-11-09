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
    var incompatibleMismatches: [GameVersionMismatch] = []

    func incompatibleVersion(_ mismatch: GameVersionMismatch) {
        incompatibleMismatches.append(mismatch)
    }

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

    /// The SharePlay participant the mock treats as the game master's.
    var sharePlayMasterParticipantID: UUID?
    var receivedSharePlayHandler: ((GameNetworkModel, UUID) -> Void)?
    var receivedSharePlayHistory: [GameNetworkModel] = []
    var calledLostConnection = 0
    var calledReady = 0
    var calledReceived = 0
    var calledFileReceived = 0
    var calledFileLoadFailed = 0
    var incompatibleMismatches: [GameVersionMismatch] = []

    func incompatibleVersion(_ mismatch: GameVersionMismatch) {
        incompatibleMismatches.append(mismatch)
    }

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
        if model.sender.isMaster {
            sharePlayMasterParticipantID = participantId
        }
        receivedSharePlayHandler?(model, participantId)
    }

    func receivedFile(_ model: GameNetworkModel) {
        calledFileReceived += 1
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) {
        calledFileLoadFailed += 1
    }

    func isSharePlayMasterParticipant(id: UUID) -> Bool {
        sharePlayMasterParticipantID == id
    }
}
