// @copyright André Trettin

import Foundation
import Network

@testable import RPGGame

final class MasterNetworkStoreDelegateMock: MasterNetworkStoreDelegate, @unchecked Sendable {
    var calledLostPlayer = 0
    var calledReady = 0
    var calledReceived = 0
    var calledFileReceived = 0
    
    func lostPlayer(for connectionId: ConnectionController.ID) {
        calledLostPlayer += 1
    }
    
    func ready(for _: ConnectionController.ID) {
        calledReady += 1
    }
    
    func received(_: GameNetworkModel, connectionId: ConnectionController.ID?) {
        calledReceived += 1
    }
    
    func receivedFile(_ model: GameNetworkModel) {
        calledFileReceived += 1
    }
}

final class PlayerNetworkStoreDelegateMock: PlayerNetworkStoreDelegate, @unchecked Sendable {

    var calledLostConnection = 0
    var calledReady = 0
    var calledReceived = 0
    var calledFileReceived = 0

    func lostConnection() {
        calledLostConnection += 1
    }

    func ready() {
        calledReady += 1
    }

    func received(_: GameNetworkModel) {
        calledReceived += 1
    }

    func receivedFile(_ model: GameNetworkModel) {
        calledFileReceived += 1
    }
}
