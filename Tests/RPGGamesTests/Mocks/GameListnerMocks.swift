// @copyright André Trettin

import Foundation
import Network

@testable import RPGGame

final class GameListnerAbstractionMock: ListenerControllable, @unchecked Sendable {
    var calledStopListening = 0
    func stopListnening() {
        calledStopListening += 1
    }
    
    var calledStartListening = 0
    func startListening() {
        calledStartListening += 1
    }
}

final class GameListnerDelegateMock: ListenerControllerDelegate, @unchecked Sendable {
    var calledCancelled = 0
    var calledNewConnection = 0

    func cancelled() {
        calledCancelled += 1
    }

    func newConnection(for _: NWConnection) {
        calledNewConnection += 1
    }
}
