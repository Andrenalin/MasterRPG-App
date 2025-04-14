// @copyright André Trettin

import Foundation

@testable import RPGGame

final class PlayerStoreAbstractionMock: PlayerNetworkControllable, @unchecked Sendable {
    @MainActor
    init(browserController: BrowserController = BrowserController(), networkModel: PlayerNetworkNodel = PlayerNetworkNodel(), calledStop: Int = 0, calledToggleConnection: Int = 0, calledRequest: Int = 0, requestData: (any MessageMapper)? = nil) {
        self.browserController = browserController
        self.networkModel = networkModel
        self.calledStop = calledStop
        self.calledToggleConnection = calledToggleConnection
        self.calledRequest = calledRequest
        self.requestData = requestData
    }
    
    let browserController: BrowserController
    let networkModel: PlayerNetworkNodel

    var calledStop = 0
    var calledToggleConnection = 0
    var calledRequest = 0

    func toggleConnection(to _: BrowserDeviceModel) {
        calledToggleConnection += 1
    }

    func stop() {
        calledStop += 1
    }

    var requestData: MessageMapper?
    func request(with data: MessageMapper?) {
        calledRequest += 1
        requestData = data
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
