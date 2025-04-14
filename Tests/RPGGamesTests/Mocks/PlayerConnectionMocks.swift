// @copyright André Trettin

import Foundation

@testable import RPGGame

final class PlayerConnectionDelegateMock: ConnectionControllerDelegate, @unchecked Sendable {
    var calledLostConnection = 0
    var calledReadyConnection = 0
    var calledReceivedData = 0
    var calledFailed = 0

    func received(data: Data?, for id: RPGGame.ConnectionController.ID) async {
        calledReceivedData += 1
    }

    func failed(with error: String?, for id: RPGGame.ConnectionController.ID) async {
        calledFailed += 1
    }

    func lostConnection(for id: RPGGame.ConnectionController.ID) async {
        calledLostConnection += 1
    }

    func readyConnection(for id: RPGGame.ConnectionController.ID) async {
        calledReadyConnection += 1
    }
}
