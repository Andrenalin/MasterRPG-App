// @copyright André Trettin

import Foundation

@testable import RPGGame

final class MasterNetworkControllableMock: MasterNetworkControllable, @unchecked Sendable {
    @MainActor
    init(networkModel: MasterNetworkNodel = MasterNetworkNodel(name: "MasterTestName"), calledStartStreaming: Int = 0, calledStopStreaming: Int = 0, calledToggleStreaming: Int = 0, calledStartProxyStreaming: Int = 0, calledSendResponseId: Int = 0, calledSendResponseAll: Int = 0, calledSendResponseExcept: Int = 0, sendResponseData: (any MessageMapper)? = nil) {
        self.networkModel = networkModel
        self.calledStartStreaming = calledStartStreaming
        self.calledStopStreaming = calledStopStreaming
        self.calledToggleStreaming = calledToggleStreaming
        self.calledStartProxyStreaming = calledStartProxyStreaming
        self.calledSendResponseId = calledSendResponseId
        self.calledSendResponseAll = calledSendResponseAll
        self.calledSendResponseExcept = calledSendResponseExcept
        self.sendResponseData = sendResponseData
    }
    
    let networkModel: MasterNetworkNodel

    var calledStartStreaming = 0
    var calledStopStreaming = 0
    var calledToggleStreaming = 0
    var calledStartProxyStreaming = 0

    var calledSendResponseId = 0
    var calledSendResponseAll = 0
    var calledSendResponseExcept = 0

    func startStreaming() {
        calledStartStreaming += 1
    }

    func stopStreaming() {
        calledStopStreaming += 1
    }

    func toggleStreaming() {
        calledToggleStreaming += 1
    }

    func startProxyStreaming() {
        calledStartProxyStreaming += 1
    }

    func sendResponse(data netData: MessageMapper?, id _: ConnectionController.ID) {
        calledSendResponseId += 1
        sendResponseData = netData
    }

    var sendResponseData: MessageMapper?
    func sendResponse(data netData: MessageMapper?) {
        calledSendResponseAll += 1
        sendResponseData = netData
    }

    func sendResponse(data _: MessageMapper?, except _: ConnectionController.ID) {
        calledSendResponseExcept += 1
    }
}

final class MasterNetworkControllerDelegateMock: MasterNetworkControllerDelegate, @unchecked Sendable {
    var calledLostPlayer = 0
    var calledReady = 0
    var calledReceived = 0

    func masterLostPlayer(with _: ConnectionController.ID) async {
        calledLostPlayer += 1
    }

    func masterReady(for _: ConnectionController.ID) async {
        calledReady += 1
    }

    func masterReceived(data _: Data?, for _: ConnectionController.ID, fileJournal: Bool) async {
        calledReceived += 1
    }
}
