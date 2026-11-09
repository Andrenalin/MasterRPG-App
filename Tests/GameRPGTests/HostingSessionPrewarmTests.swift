// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Synchronization
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §3.5: starting to host must not read the Keychain on the main
/// thread when the prewarm of the stored hosting session is still running.
@Suite("Hosting session prewarm")
@MainActor
struct HostingSessionPrewarmTests {

    @Test("hosting waits for the prewarm instead of reading the Keychain on the main thread")
    func hostingWaitsForPrewarm() async {
        // Given - a slow Keychain that remembers where it was read.
        let storage = ThreadRecordingJoinCodeStorage(readDelay: 0.2)
        let controller = MasterNetworkController(
            name: "Prewarm",
            delegate: MasterNetworkControllerDelegateMock(),
            listenerBuilder: { _, _, _, _, _, _ in GameListenerAbstractionMock() as any ListenerManaging },
            hostingSessions: HostingSessionStore(storage: storage)
        )

        // When - hosting starts right after the controller was created, as it does after launch.
        await controller.waitForHostingSessionReady()
        controller.startStreaming(passcode: "1234")

        // Then
        #expect(storage.readsOnMainThread == 0)
        #expect(storage.readCount >= 1)
        #expect(controller.networkModel.isStreaming)
        #expect(!controller.networkModel.sessionId.isEmpty)
    }

    @Test("the stored session is reused after the prewarm")
    func storedSessionIsReused() async {
        let storage = ThreadRecordingJoinCodeStorage(
            values: [HostingSessionStore.masterKey: "1234 stored-session"]
        )
        let controller = MasterNetworkController(
            name: "Prewarm",
            delegate: MasterNetworkControllerDelegateMock(),
            listenerBuilder: { _, _, _, _, _, _ in GameListenerAbstractionMock() as any ListenerManaging },
            hostingSessions: HostingSessionStore(storage: storage)
        )

        await controller.waitForHostingSessionReady()
        controller.startStreaming(passcode: "1234")

        #expect(controller.networkModel.sessionId == "stored-session")
        #expect(storage.readsOnMainThread == 0)
    }
}

private final class ThreadRecordingJoinCodeStorage: JoinCodeStorage {
    private struct State {
        var values: [String: String]
        var readCount = 0
        var readsOnMainThread = 0
    }

    private let state: Mutex<State>
    private let readDelay: Double

    init(values: [String: String] = [:], readDelay: Double = 0) {
        state = Mutex(State(values: values))
        self.readDelay = readDelay
    }

    var readCount: Int { state.withLock { $0.readCount } }
    var readsOnMainThread: Int { state.withLock { $0.readsOnMainThread } }

    func read(forKey key: String) -> JoinCodeReadResult {
        if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
        let onMain = Thread.isMainThread
        return state.withLock { state in
            state.readCount += 1
            if onMain { state.readsOnMainThread += 1 }
            return state.values[key].map(JoinCodeReadResult.found) ?? .notFound
        }
    }

    func set(_ value: String, forKey key: String) -> Bool {
        state.withLock { $0.values[key] = value }
        return true
    }

    func remove(forKey key: String) -> Bool {
        state.withLock { _ = $0.values.removeValue(forKey: key) }
        return true
    }
}
#endif
