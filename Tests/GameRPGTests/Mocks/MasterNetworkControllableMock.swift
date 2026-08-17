// @copyright André Trettin

import CoreRPG
import Foundation

@testable import GameRPG

final class MasterNetworkControllableMock: MasterNetworkControllable, @unchecked Sendable {
    @MainActor
    init(networkModel: MasterNetworkModel = MasterNetworkModel(name: "MasterTestName"), calledStartStreaming: Int = 0, calledStopStreaming: Int = 0, calledToggleStreaming: Int = 0, calledStartProxyStreaming: Int = 0, calledSendResponseId: Int = 0, calledSendResponseAll: Int = 0, calledSendResponseExcept: Int = 0, sendResponseData: (any MessageMapper)? = nil) {
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
    
    let networkModel: MasterNetworkModel

    var calledStartStreaming = 0
    var calledStopStreaming = 0
    var calledToggleStreaming = 0
    var calledStartProxyStreaming = 0

    var calledSendResponseId = 0
    var calledSendResponseAll = 0
    var calledSendResponseExcept = 0
    var sendResponseExceptData: MessageMapper?
    var lastExceptId: ConnectionController.ID?

    var lastPasscode: String?

    func startStreaming(passcode: String) {
        calledStartStreaming += 1
        lastPasscode = passcode
    }

    func stopStreaming() {
        calledStopStreaming += 1
    }

    func toggleStreaming(passcode: String) {
        calledToggleStreaming += 1
        lastPasscode = passcode
    }

    func startProxyStreaming(passcode: String) {
        calledStartProxyStreaming += 1
        lastPasscode = passcode
    }

    /// Stubbed delivery result — set to false to exercise the broadcast fallback.
    var sendResponseIdResult = true

    @discardableResult
    func sendResponse(data netData: MessageMapper?, id _: ConnectionController.ID) -> Bool {
        calledSendResponseId += 1
        sendResponseData = netData
        if let netData {
            sendResponseHistory.append(netData)
        }
        return sendResponseIdResult
    }

    var sendResponseData: MessageMapper?
    var sendResponseHistory: [MessageMapper] = []
    func sendResponse(data netData: MessageMapper?) {
        calledSendResponseAll += 1
        sendResponseData = netData
        if let netData {
            sendResponseHistory.append(netData)
        }
    }

    func sendResponse(data netData: MessageMapper?, except connectionId: ConnectionController.ID) {
        calledSendResponseExcept += 1
        sendResponseExceptData = netData
        lastExceptId = connectionId
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
