// @copyright André Trettin

import Foundation
import Network

@testable import GameRPG

final class GameListenerAbstractionMock: ListenerManaging, @unchecked Sendable {
    var calledStopListening = 0
    @MainActor func stopListening() {
        calledStopListening += 1
    }

    var calledStartListening = 0
    @MainActor func startListening() {
        calledStartListening += 1
    }
}

final class GameListenerDelegateMock: ListenerManagerDelegate, @unchecked Sendable {
    var calledCancelled = 0
    var calledNewConnection = 0

    func listenerCancelled() async {
        calledCancelled += 1
    }

    func listenerNewConnection(_ connection: NWConnection) async {
        calledNewConnection += 1
    }
}
