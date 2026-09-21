// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// Real loopback handshakes with the app's TLS-PSK parameters.
@Suite("TLS-PSK passcode handshake")
struct TLSPasscodeHandshakeTests {
    private final class Box: @unchecked Sendable {
        var port: NWEndpoint.Port?
        var listener: NWListener?
        var accepted: [NWConnection] = []
    }

    private func startListener(passcode: String) async throws -> (NWListener, NWEndpoint.Port, Box) {
        let box = Box()
        let listener = try NWListener(using: NWParameters(passcode: passcode))
        box.listener = listener
        listener.newConnectionHandler = { connection in
            box.accepted.append(connection)
            connection.start(queue: .global())
        }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port, once.take() { continuation.resume(returning: port) }
                case .failed(let error):
                    if once.take() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        return (listener, port, box)
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if taken { return false }; taken = true; return true }
    }

    private func outcome(port: NWEndpoint.Port, passcode: String) async -> String {
        let connection = NWConnection.connection(endpoint: .hostPort(host: "127.0.0.1", port: port), passcode: passcode)
        return await withCheckedContinuation { continuation in
            let once = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.take() { continuation.resume(returning: "ready") }
                case .failed(let error):
                    if once.take() { continuation.resume(returning: "failed: \(error)") }
                case .waiting(let error):
                    if once.take() { continuation.resume(returning: "waiting: \(error)") }
                default: break
                }
            }
            connection.start(queue: .global())
        }
    }

    @Test("Same code connects; a different code is rejected")
    func sameAndDifferentCodes() async throws {
        let (listener, port, _) = try await startListener(passcode: "1234")
        defer { listener.cancel() }

        let same = await outcome(port: port, passcode: "1234")
        let different = await outcome(port: port, passcode: "9999")

        // Regression: a UTF-16 PSK identity contains NUL bytes and never matched, so even the
        // right code failed with "unknown PSK identity".
        #expect(same == "ready", "matching code: \(same)")
        #expect(different != "ready", "different code: \(different)")
        #expect(!different.contains("-9864"), "a wrong code must fail on the key, not on the identity: \(different)")
    }

    @Test("ConnectionController reports a wrong code as an authentication failure")
    func wrongCodeIsReportedAsAuthenticationFailure() async throws {
        let (listener, port, _) = try await startListener(passcode: "1234")
        defer { listener.cancel() }
        let delegate = OutcomeDelegate()
        let controller = ConnectionController(
            id: UUID(),
            endpoint: .hostPort(host: "127.0.0.1", port: port),
            passcode: "9999",
            delegate: delegate
        )

        await controller.startConnection()
        let result = await delegate.firstOutcome(timeout: .seconds(10))
        await controller.cancel()

        #expect(result == "failed(auth: true)", "\(result)")
    }

    @Test("ConnectionController becomes ready with the right code")
    func rightCodeBecomesReady() async throws {
        let (listener, port, _) = try await startListener(passcode: "1234")
        defer { listener.cancel() }
        let delegate = OutcomeDelegate()
        let controller = ConnectionController(
            id: UUID(),
            endpoint: .hostPort(host: "127.0.0.1", port: port),
            passcode: "1234",
            delegate: delegate
        )

        await controller.startConnection()
        let result = await delegate.firstOutcome(timeout: .seconds(10))
        await controller.cancel()

        #expect(result == "ready", "\(result)")
    }

    private final class OutcomeDelegate: ConnectionControllerDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [String] = []

        private func record(_ outcome: String) {
            lock.withLock { outcomes.append(outcome) }
        }

        func received(data: Data?, for id: ConnectionController.ID) async {}
        func failed(with error: String?, isAuthenticationFailure: Bool, for id: ConnectionController.ID) async {
            record("failed(auth: \(isAuthenticationFailure))")
        }
        func lostConnection(for id: ConnectionController.ID) async { record("lost") }
        func readyConnection(for id: ConnectionController.ID) async { record("ready") }

        private func firstRecorded() -> String? {
            lock.withLock { outcomes.first }
        }

        func firstOutcome(timeout: Duration) async -> String {
            let deadline = ContinuousClock.now.advanced(by: timeout)
            while ContinuousClock.now < deadline {
                if let first = firstRecorded() { return first }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return "timeout"
        }
    }
}
#endif
