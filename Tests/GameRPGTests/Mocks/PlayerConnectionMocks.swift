// @copyright André Trettin

import Foundation
import Synchronization

@testable import GameRPG

final class PlayerConnectionDelegateMock: ConnectionControllerDelegate, Sendable {
    /// Called from the connection's own tasks while the test polls the counters, so they sit
    /// behind a lock (CODE_AUDIT_TestGaps §3.5: ThreadSanitizer reported the unprotected counters).
    private struct Counters {
        var lostConnection = 0
        var readyConnection = 0
        var receivedData = 0
        var failed = 0
    }

    private let counters = Mutex(Counters())

    var calledLostConnection: Int { counters.withLock { $0.lostConnection } }
    var calledReadyConnection: Int { counters.withLock { $0.readyConnection } }
    var calledReceivedData: Int { counters.withLock { $0.receivedData } }
    var calledFailed: Int { counters.withLock { $0.failed } }

    func received(data: Data?, for id: ConnectionController.ID) async {
        counters.withLock { $0.receivedData += 1 }
    }

    func failed(with error: String?, isAuthenticationFailure: Bool, for id: ConnectionController.ID) async {
        counters.withLock { $0.failed += 1 }
    }

    func lostConnection(for id: ConnectionController.ID) async {
        counters.withLock { $0.lostConnection += 1 }
    }

    func readyConnection(for id: ConnectionController.ID) async {
        counters.withLock { $0.readyConnection += 1 }
    }
}
