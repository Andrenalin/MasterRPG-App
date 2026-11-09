// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

@MainActor
final class MasterNetworkController: Sendable {
    /// Held weakly here on the main actor: a frame goes from its connection straight to the
    /// delegate, not through an actor that only held the reference.
    /// See CODE_AUDIT_Game_Shareplay §7.4.
    weak var delegate: (any MasterNetworkControllerDelegate)?
    /// Arguments: name, supporter tier, proxy, passcode, session id, delegate.
    let listenerBuilder: @MainActor @Sendable (String, SupporterTier, Bool, String, String, any ListenerManagerDelegate) -> any ListenerManaging
    let browserConnectionBuilder: @MainActor @Sendable (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable
    let networkModel: MasterNetworkModel
    private let hostingSessions: HostingSessionStore
    var browserConnectionEndpoints: [ConnectionController.ID: NWEndpoint] = [:]
    // See CODE_AUDIT §6.1: throttles repeated bad-passcode attempts on the inbound
    // listener. connectToPlayer's outbound reconnect dial-outs are never throttled —
    // this device is the one connecting there, not receiving an unknown attempt.
    // See CODE_AUDIT §9.7 for why this is the shared `ConnectionThrottleTracker`
    // rather than a hand-rolled throttle + pending-sources dictionary here.
    let connectionThrottle = ConnectionThrottleTracker()

    /// Outbound connections that reached `.ready`; anything else is still dialing.
    var establishedConnectionIds: Set<ConnectionController.ID> = []
    /// Failed redials per fallback endpoint since it last connected, and the pending retry.
    var redialAttempts: [NWEndpoint: Int] = [:]
    var redialTasks: [NWEndpoint: Task<Void, Never>] = [:]
    var listenerRestarts = ListenerRestartScheduler()
    /// Serializes outbound sends: each send encodes off the main actor and only hands its
    /// frame to the connections after the previous send did, so a small message sent after
    /// a large one can no longer overtake it (a pin/map-state arriving before its map).
    /// See CODE_AUDIT_18 §3.15.
    private var outboundChain: Task<Void, Never>?
    private var hostingSessionPrewarmTask: Task<Void, Never>?

    static func gameListenerBuilder() -> @MainActor @Sendable (String, SupporterTier, Bool, String, String, any ListenerManagerDelegate) -> any ListenerManaging {
        return { name, supporterTier, proxy, passcode, sessionId, delegate in
            let manager = ListenerManager(name: name, supporterTier: supporterTier, serviceType: proxy ? .proxyServer : .player, passcode: passcode, sessionId: sessionId)
            manager.delegate = delegate
            return manager
        }
    }

    static func gameBrowserConnectionBuilder() -> @MainActor @Sendable (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable {
        return { endpoint, passcode, delegate in
            ConnectionController(id: UUID(), endpoint: endpoint, passcode: passcode, delegate: delegate)
        }
    }

    init(
        name: String,
        delegate: MasterNetworkControllerDelegate? = nil,
        listenerBuilder: @MainActor @Sendable @escaping (String, SupporterTier, Bool, String, String, any ListenerManagerDelegate) -> any ListenerManaging,
        browserConnectionBuilder: @MainActor @Sendable @escaping (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable = MasterNetworkController.gameBrowserConnectionBuilder(),
        hostingSessions: HostingSessionStore = .shared
    ) {
        self.networkModel = MasterNetworkModel(name: name)
        self.hostingSessions = hostingSessions
        self.delegate = delegate
        self.listenerBuilder = listenerBuilder
        self.browserConnectionBuilder = browserConnectionBuilder
        // Reads the stored hosting session off the main actor, so starting to host never waits
        // on the Keychain. The task is kept: hosting awaits it (`waitForHostingSessionReady`),
        // where a discarded task turned the race into a synchronous Keychain read on the main
        // actor. See CODE_AUDIT_20 §3.7, CODE_AUDIT_Game_Shareplay §3.5.
        hostingSessionPrewarmTask = Task { await hostingSessions.prewarm() }
        Logger.networking.debug("MasterNetworkController: Init")
    }

    deinit {
        Logger.networking.debug("MasterNetworkController: Deinit")
    }
}

// MARK: - Control

extension MasterNetworkController: MasterNetworkControllable {
    func waitForHostingSessionReady() async {
        await hostingSessionPrewarmTask?.value
    }

    func startStreaming(passcode: String) {
        Logger.networking.debug("MasterNetworkController: Start Streaming")
        beginHosting(passcode: passcode, proxy: false)
    }

    func startProxyStreaming(passcode: String) {
        Logger.networking.debug("MasterNetworkController: Start Proxy Streaming")
        beginHosting(passcode: passcode, proxy: true)
    }

    private func beginHosting(passcode: String, proxy: Bool) {
        resetConnections()
        networkModel.isStreaming = true
        networkModel.passcode = passcode
        networkModel.isProxyHosting = proxy
        // Stable while the code is: players waiting to reconnect after the master ended and
        // restarted the game still advertise it, so they are redialed.
        networkModel.sessionId = hostingSessions.sessionId(forPasscode: passcode, proxy: proxy)
        listenerRestarts.reset()
        startListener()

        networkModel.browserManager = BrowserManager(serviceType: proxy ? .proxyClient : .master, recordsRemovals: false)
        networkModel.browserManager?.start()
        observeConnections()
    }

    func startListener() {
        networkModel.listener = listenerBuilder(
            networkModel.name,
            networkModel.supporterTier,
            networkModel.isProxyHosting,
            networkModel.passcode,
            networkModel.sessionId,
            self
        )
        networkModel.listener?.startListening()
        listenerRestarts.listenerStarted()
        // `listenerStatus` becomes `.running` only once `listenerReady()` fires for the
        // listener's real `.ready` event — see §5.22. Until then hosting reads as starting
        // (not "stopped"); a restart keeps showing `.restarting`. See CODE_AUDIT_18 §5.15.
        if networkModel.listenerStatus != .restarting {
            networkModel.listenerStatus = .starting
        }
    }

    /// Restarts hosting services that stopped while the app was not active, without dropping
    /// players that are still connected. See CODE_AUDIT_Join §5.3.
    func resumeAfterActivation() {
        guard networkModel.isStreaming else { return }
        if networkModel.listener == nil {
            listenerRestarts.reset()
            startListener()
        }
        if let browser = networkModel.browserManager {
            if !browser.isBrowsing {
                browser.start()
            }
        } else {
            // Recreate a browser that was dropped while hosting, so returning players are
            // redialed again. See CODE_AUDIT_18 §5.14.
            networkModel.browserManager = BrowserManager(serviceType: networkModel.isProxyHosting ? .proxyClient : .master, recordsRemovals: false)
            networkModel.browserManager?.start()
            observeConnections()
        }
    }

    func stopStreaming() {
        Logger.networking.debug("MasterNetworkController: Stop Streaming")

        resetConnections()
        networkModel.isStreaming = false
    }

    func toggleStreaming(passcode: String) {
        if networkModel.isStreaming {
            stopStreaming()
        } else {
            startStreaming(passcode: passcode)
        }
    }

    private func resetConnections() {
        networkModel.observeConnectionsTask?.cancel()
        networkModel.observeConnectionsTask = nil
        networkModel.connectionStartTasks.values.forEach { $0.cancel() }
        networkModel.connectionStartTasks.removeAll()
        networkModel.browserManager?.stop()
        networkModel.browserManager = nil
        networkModel.listener?.stopListening()
        networkModel.listener = nil
        networkModel.browserConnections = []
        browserConnectionEndpoints = [:]
        establishedConnectionIds = []
        redialTasks.values.forEach { $0.cancel() }
        redialTasks = [:]
        redialAttempts = [:]
        listenerRestarts.cancel()
        // A new hosting session's first send must not wait for the old session's tail.
        // See CODE_AUDIT_19 §3.13.
        outboundChain = nil
        networkModel.listenerStatus = .stopped
        // Fire-and-forget: `resetConnections()` is synchronous (called from
        // the non-async `startStreaming`/`stopStreaming`), and clearing
        // pending entries has no ordering dependency on anything else here.
        Task { await connectionThrottle.clearAllPending() }
        // Cancel explicitly: dropping the reference would not close the socket at once, and
        // `cancel()` is what reports the loss and ends the peer's connection now, instead of
        // leaving it connected and black-holed. See CODE_AUDIT_16 §3.1, CODE_AUDIT_20 §3.9.
        networkModel.connectionGeneration += 1
        let dropped = networkModel.connections
        networkModel.connections = []
        Task {
            for connection in dropped {
                await connection.cancel()
            }
        }
    }
}

// MARK: - Send

extension MasterNetworkController {
    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        guard let connection = networkModel.connections.first(where: { $0.id == id }) else { return false }
        await sendOrdered(data, to: [connection])
        return true
    }

    func sendResponse(data: MessageMapper?) async {
        let connections = networkModel.connections
        guard !connections.isEmpty else { return }
        await sendOrdered(data, to: connections)
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        let connections = networkModel.connections.filter { $0.id != except }
        guard !connections.isEmpty else { return }
        await sendOrdered(data, to: connections)
    }

    private func sendOrdered(_ data: MessageMapper?, to connections: [any ConnectionControllable]) async {
        // Encoding starts right away, concurrently with earlier sends; only the hand-off to
        // the connections is chained, so a small message no longer also waits for its own
        // encode behind a multi-MB map encode. See CODE_AUDIT_19 §3.13.
        let encoding = Task { await encodedOffMain(data) }
        let previous = outboundChain
        let send = Task { @MainActor in
            await previous?.value
            // A nil encoding (encode failure) used to go out as a zero-length frame, which
            // the receiver treats as the peer closing the connection. See CODE_AUDIT_18 §3.15.
            guard let encodedData = await encoding.value else {
                Logger.networking.error("MasterNetworkController: Skipped sending a message that could not be encoded")
                return
            }
            await withDiscardingTaskGroup { group in
                for connection in connections {
                    group.addTask {
                        await connection.response(type: .gameData, encodedContent: encodedData)
                    }
                }
            }
        }
        outboundChain = send
        await send.value
    }
}

// MARK: - MasterConnectionDelegate

extension MasterNetworkController: ConnectionControllerDelegate {
    @MainActor
    func failed(with error: String?, isAuthenticationFailure: Bool = true, for id: ConnectionController.ID) async {
        // Only a TLS/passcode rejection is evidence of a bad-passcode guess.
        // An ordinary transport-layer failure (Wi-Fi drop, timeout,
        // unreachable peer) is exactly what a legitimate player's automatic
        // reconnect retry can hit, and counting it toward the lockout would
        // let a flaky network eventually throttle a real peer out of
        // reconnecting. See CODE_AUDIT_Reconnect §6.1.
        if isAuthenticationFailure {
            await connectionThrottle.resolve(id: id, succeeded: false)
        } else {
            await connectionThrottle.clear(id: id)
        }
        await removeConnectionAndNotify(id: id)
    }

    /// A clean cancellation (peer disconnected, backgrounded, network drop) is
    /// not a bad-passcode attempt, unlike `failed(with:for:)` above — clear its
    /// pending entry without penalizing the source.
    @MainActor
    func lostConnection(for id: ConnectionController.ID) async {
        await connectionThrottle.clear(id: id)
        await removeConnectionAndNotify(id: id)
    }

    @MainActor
    func readyConnection(for id: ConnectionController.ID) async {
        await connectionThrottle.resolve(id: id, succeeded: true)
        establishedConnectionIds.insert(id)
        if let endpoint = browserConnectionEndpoints[id] {
            redialAttempts.removeValue(forKey: endpoint)
        }
        await delegate?.masterReady(for: id)
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate?.masterReceived(data: data, for: id)
    }
}
