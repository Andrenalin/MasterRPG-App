// @copyright André Trettin

import Foundation
import Network

@testable import GameRPG

final class ConnectionMock: ConnectionAbstraction {
    var calledSend = 0
    var calledStart = 0
    var calledCancel = 0
    var calledReceiveMessage = 0

    var debugDescription: String {
        "ConnectionMock"
    }

    var stateUpdateHandler: (@Sendable (_ state: NWConnection.State) -> Void)? = nil

    func cancel() {
        calledCancel += 1
    }

    func send(content _: Data?, contentContext _: NWConnection.ContentContext, isComplete _: Bool, completion _: NWConnection.SendCompletion) {
        calledSend += 1
    }

    func start(queue _: DispatchQueue) {
        calledStart += 1
    }

    func receiveMessage(completion _: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void) {
        calledReceiveMessage += 1
    }
}
