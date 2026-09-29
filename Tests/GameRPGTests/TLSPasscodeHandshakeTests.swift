// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// Real loopback handshakes with the app's TLS-PSK parameters on `GameListener`/`GameConnection`.
@Suite("TLS-PSK passcode handshake")
struct TLSPasscodeHandshakeTests {
    /// A listener with the app's parameters. Every accepted connection is wrapped in a
    /// `ConnectionController` and started, as `MasterNetworkController` does: an accepted
    /// connection only starts (and completes its handshake) once something receives on it.
    private final class Server: @unchecked Sendable {
        let delegate = OutcomeDelegate()
        private let store = ControllerStore()
        private var runTask: Task<Void, Never>?

        var accepted: [ConnectionController] {
            store.controllers
        }

        func start(passcode: String) async throws -> NWEndpoint.Port {
            let listener = try GameListener(using: GameNetworkParameters.builder(passcode: passcode))
            let (ports, portContinuation) = AsyncStream.makeStream(of: NWEndpoint.Port?.self)
            listener.onStateUpdate { listener, state in
                switch state {
                case .ready:
                    portContinuation.yield(listener.port)
                    portContinuation.finish()
                case .failed, .cancelled:
                    portContinuation.finish()
                default:
                    break
                }
            }
            let delegate = delegate
            let store = store
            runTask = Task {
                try? await listener.run { connection in
                    let controller = ConnectionController(id: UUID(), connection: connection, delegate: delegate)
                    store.append(controller)
                    await controller.startConnection()
                }
            }
            var iterator = ports.makeAsyncIterator()
            guard let port = await iterator.next() ?? nil else { throw NWError.posix(.EADDRNOTAVAIL) }
            return port
        }

        func stopListening() {
            runTask?.cancel()
        }

        func stop() async {
            stopListening()
            for controller in accepted {
                await controller.cancel()
            }
        }
    }

    /// Holds the accepted controllers, so the listener's handler does not capture `Server`.
    private final class ControllerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [ConnectionController] = []

        var controllers: [ConnectionController] {
            lock.withLock { stored }
        }

        func append(_ controller: ConnectionController) {
            lock.withLock { stored.append(controller) }
        }
    }

    private func outcome(port: NWEndpoint.Port, passcode: String) async -> String {
        let connection = GameConnection.game(to: .hostPort(host: "127.0.0.1", port: port), passcode: passcode)
        let (states, continuation) = AsyncStream.makeStream(of: String.self)
        connection.onStateUpdate { _, state in
            switch state {
            case .ready:
                continuation.yield("ready")
            case .failed(let error):
                continuation.yield("failed: \(error)")
            case .waiting(let error):
                continuation.yield("waiting: \(error)")
            default:
                break
            }
        }
        // A `GameConnection` starts with its first receive; cancelling it cancels the connection.
        let receive = Task { _ = try? await connection.receive() }
        defer { receive.cancel() }
        var iterator = states.makeAsyncIterator()
        return await iterator.next() ?? "none"
    }

    private func client(port: NWEndpoint.Port, passcode: String, delegate: OutcomeDelegate) -> ConnectionController {
        ConnectionController(
            id: UUID(),
            endpoint: .hostPort(host: "127.0.0.1", port: port),
            passcode: passcode,
            delegate: delegate
        )
    }

    @Test("Same code connects; a different code is rejected")
    func sameAndDifferentCodes() async throws {
        let server = Server()
        let port = try await server.start(passcode: "1234")

        let same = await outcome(port: port, passcode: "1234")
        let different = await outcome(port: port, passcode: "9999")
        await server.stop()

        // Regression: a UTF-16 PSK identity contains NUL bytes and never matched, so even the
        // right code failed with "unknown PSK identity".
        #expect(same == "ready", "matching code: \(same)")
        #expect(different != "ready", "different code: \(different)")
        #expect(!different.contains("-9864"), "a wrong code must fail on the key, not on the identity: \(different)")
    }

    @Test("ConnectionController reports a wrong code as an authentication failure")
    func wrongCodeIsReportedAsAuthenticationFailure() async throws {
        let server = Server()
        let port = try await server.start(passcode: "1234")
        let delegate = OutcomeDelegate()
        let controller = client(port: port, passcode: "9999", delegate: delegate)

        await controller.startConnection()
        let result = await delegate.outcome(at: 0, timeout: .seconds(10))
        await controller.cancel()
        await server.stop()

        #expect(result == "failed(auth: true)", "\(result)")
    }

    @Test("ConnectionController becomes ready with the right code")
    func rightCodeBecomesReady() async throws {
        let server = Server()
        let port = try await server.start(passcode: "1234")
        let delegate = OutcomeDelegate()
        let controller = client(port: port, passcode: "1234", delegate: delegate)

        await controller.startConnection()
        let result = await delegate.outcome(at: 0, timeout: .seconds(10))
        await controller.cancel()
        await server.stop()

        #expect(result == "ready", "\(result)")
    }

    @Test("Framed game messages reach the other side in order, both ways")
    func messagesRoundTrip() async throws {
        let server = Server()
        let port = try await server.start(passcode: "1234")
        let delegate = OutcomeDelegate()
        let controller = client(port: port, passcode: "1234", delegate: delegate)

        await controller.startConnection()
        for index in 0..<5 {
            await controller.request(type: .gameData, encodedContent: Data("request \(index)".utf8))
        }
        let serverReceived = await server.delegate.outcome(at: 5, timeout: .seconds(10))
        let accepted = try #require(server.accepted.first)
        await accepted.response(type: .gameData, encodedContent: Data("response".utf8))
        let clientReceived = await delegate.outcome(at: 1, timeout: .seconds(10))
        await controller.cancel()
        await server.stop()

        let expected = ["ready"] + (0..<5).map { "data: request \($0)" }
        #expect(Array(server.delegate.recorded.prefix(6)) == expected)
        #expect(serverReceived == "data: request 4")
        #expect(clientReceived == "data: response")
    }

    @Test("An accepted connection outlives the listener, and a local cancel reports the loss")
    func acceptedConnectionOutlivesListener() async throws {
        let server = Server()
        let port = try await server.start(passcode: "1234")
        let delegate = OutcomeDelegate()
        let controller = client(port: port, passcode: "1234", delegate: delegate)
        await controller.startConnection()
        #expect(await server.delegate.outcome(at: 0, timeout: .seconds(10)) == "ready")

        // The player's reconnect listener is retired while its connection stays up.
        server.stopListening()
        try await Task.sleep(for: .milliseconds(200))
        await controller.request(type: .gameData, encodedContent: Data("after listener".utf8))
        let received = await server.delegate.outcome(at: 1, timeout: .seconds(10))

        await controller.cancel()
        let clientTerminal = await delegate.outcome(at: 1, timeout: .seconds(10))
        let serverTerminal = await server.delegate.outcome(at: 2, timeout: .seconds(10))
        await server.stop()

        #expect(received == "data: after listener")
        #expect(clientTerminal == "lost")
        #expect(serverTerminal == "failed(auth: false)", "the peer closing is reported: \(serverTerminal)")
    }

    private final class OutcomeDelegate: ConnectionControllerDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [String] = []

        var recorded: [String] {
            lock.withLock { outcomes }
        }

        private func record(_ outcome: String) {
            lock.withLock { outcomes.append(outcome) }
        }

        func received(data: Data?, for id: ConnectionController.ID) async {
            record("data: \(data.map { String(decoding: $0, as: UTF8.self) } ?? "nil")")
        }
        func failed(with error: String?, isAuthenticationFailure: Bool, for id: ConnectionController.ID) async {
            record("failed(auth: \(isAuthenticationFailure))")
        }
        func lostConnection(for id: ConnectionController.ID) async { record("lost") }
        func readyConnection(for id: ConnectionController.ID) async { record("ready") }

        func outcome(at index: Int, timeout: Duration) async -> String {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                let outcomes = recorded
                if outcomes.count > index { return outcomes[index] }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return "timeout"
        }
    }
}
#endif
