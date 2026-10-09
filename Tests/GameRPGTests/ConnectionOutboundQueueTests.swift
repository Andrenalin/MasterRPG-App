// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// CODE_AUDIT_21 §6.3: frames for a peer that does not read were kept without a limit.
///
/// The connection is never started, so nothing leaves the queue: the state of a peer that has
/// stopped reading.
@Suite("Connection outbound queue limit")
struct ConnectionOutboundQueueTests {
    private func stalledConnection(delegate: PlayerConnectionDelegateMock) -> ConnectionController {
        ConnectionController(
            id: UUID(),
            endpoint: .hostPort(host: "127.0.0.1", port: 9),
            passcode: "1234",
            delegate: delegate
        )
    }

    /// The failure is reported from a task of its own.
    private func waitForFailure(_ delegate: PlayerConnectionDelegateMock) async {
        for _ in 0..<200 where delegate.calledFailed == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A connection over its queue limit is dropped and reported once")
    func queueOverLimitFailsTheConnection() async {
        let delegate = PlayerConnectionDelegateMock()
        let controller = stalledConnection(delegate: delegate)
        let frame = Data(count: GameLimits.maximumMessageBytes)

        // Exactly the limit is still queued.
        for _ in 0..<(GameLimits.maximumOutboundQueuedBytes / GameLimits.maximumMessageBytes) {
            await controller.response(type: .gameData, encodedContent: frame)
        }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(delegate.calledFailed == 0)

        await controller.response(type: .gameData, encodedContent: Data(count: 1))
        await waitForFailure(delegate)
        #expect(delegate.calledFailed == 1)

        // The connection is gone: a later send is ignored and reports nothing more.
        await controller.response(type: .gameData, encodedContent: frame)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(delegate.calledFailed == 1)
    }

    @Test("One frame is queued whatever its size")
    func oneOversizedFrameIsQueued() async {
        let delegate = PlayerConnectionDelegateMock()
        let controller = stalledConnection(delegate: delegate)

        await controller.response(
            type: .gameData,
            encodedContent: Data(count: GameLimits.maximumOutboundQueuedBytes + 1)
        )
        try? await Task.sleep(for: .milliseconds(50))

        #expect(delegate.calledFailed == 0)
    }
}
#endif
