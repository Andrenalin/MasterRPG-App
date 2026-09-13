// @copyright André Trettin

import CoreRPG
import Foundation

@testable import GameRPG

final class PlayerStoreAbstractionMock: PlayerNetworkControllable, @unchecked Sendable {
    @MainActor
    init(browserManager: BrowserManager = BrowserManager(), networkModel: PlayerNetworkModel = PlayerNetworkModel(), calledStop: Int = 0, calledToggleConnection: Int = 0, calledRequest: Int = 0, requestData: (any MessageMapper)? = nil) {
        self.browserManager = browserManager
        self.networkModel = networkModel
        self.calledStop = calledStop
        self.calledToggleConnection = calledToggleConnection
        self.calledRequest = calledRequest
        self.requestData = requestData
    }

    let browserManager: BrowserManager
    let networkModel: PlayerNetworkModel

    var calledStop = 0
    var calledToggleConnection = 0
    var calledRequest = 0

    var lastPasscode: String?
    var toggleConnectionResult = true

    func toggleConnection(to _: BrowserGameModel, passcode: String) -> Bool {
        calledToggleConnection += 1
        lastPasscode = passcode
        return toggleConnectionResult
    }

    func stop() {
        calledStop += 1
    }

    var requestData: MessageMapper?
    var requestHistory: [MessageMapper] = []
    func request(with data: MessageMapper?) {
        calledRequest += 1
        requestData = data
        if let data {
            requestHistory.append(data)
        }
    }
}

final class PlayerStoreDelegateMock: PlayerNetworkControllerDelegate, @unchecked Sendable {
    var calledLostMaster = 0
    var calledReady = 0
    var calledReceived = 0

    func playerLostMaster() {
        calledLostMaster += 1
    }

    func playerReceived(data _: Data?) {
        calledReceived += 1
    }

    func playerReady() {
        calledReady += 1
    }
}
