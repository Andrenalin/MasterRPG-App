// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

actor MasterNetworkControllerDelegateBox {
    private weak var delegate: (any MasterNetworkControllerDelegate)?

    init(_ delegate: (any MasterNetworkControllerDelegate)?) {
        self.delegate = delegate
    }

    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        await delegate?.masterLostPlayer(with: connectionId)
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        await delegate?.masterReady(for: connectionId)
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        await delegate?.masterReceived(data: data, for: connectionId, fileJournal: fileJournal)
    }
}

@MainActor
final class MasterNetworkController: Sendable {
    private let delegate: MasterNetworkControllerDelegateBox
    /// Arguments: name, supporter tier, proxy, passcode, session id, delegate.
    let listnerBuilder: @MainActor @Sendable (String, SupporterTier, Bool, String, String, any ListenerManagerDelegate) -> any ListenerManaging
    let browserConnectionBuilder: @MainActor @Sendable (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable
    let networkModel: MasterNetworkModel
    private var browserConnectionEndpoints: [ConnectionController.ID: NWEndpoint] = [:]
    // See CODE_AUDIT §6.1: throttles repeated bad-passcode attempts on the inbound
    // listener. connectToPlayer's outbound reconnect dial-outs are never throttled —
    // this device is the one connecting there, not receiving an unknown attempt.
    // See CODE_AUDIT §9.7 for why this is the shared `ConnectionThrottleTracker`
    // rather than a hand-rolled throttle + pending-sources dictionary here.
    private let connectionThrottle = ConnectionThrottleTracker()

    /// Outbound connections that reached `.ready`; anything else is still dialing.
    private var establishedConnectionIds: Set<ConnectionController.ID> = []
    /// Failed redials per fallback endpoint since it last connected, and the pending retry.
    private var redialAttempts: [NWEndpoint: Int] = [:]
    private var redialTasks: [NWEndpoint: Task<Void, Never>] = [:]
    private var listenerRestartTask: Task<Void, Never>?
    private var listenerRestartAttempt = 0
    private var listenerStartedAt: ContinuousClock.Instant?
    /// Serializes outbound sends: each send encodes off the main actor and only hands its
    /// frame to the connections after the previous send did, so a small message sent after
    /// a large one can no longer overtake it (a pin/map-state arriving before its map).
    /// See CODE_AUDIT_18 §3.15.
    private var outboundChain: Task<Void, Never>?

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
        listnerBuilder: @MainActor @Sendable @escaping (String, SupporterTier, Bool, String, String, any ListenerManagerDelegate) -> any ListenerManaging,
        browserConnectionBuilder: @MainActor @Sendable @escaping (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable = MasterNetworkController.gameBrowserConnectionBuilder()
    ) {
        self.networkModel = MasterNetworkModel(name: name)
        self.delegate = MasterNetworkControllerDelegateBox(delegate)
        self.listnerBuilder = listnerBuilder
        self.browserConnectionBuilder = browserConnectionBuilder
        Logger.networking.debug("MasterNetworkController: Init")
    }

    deinit {
        Logger.networking.debug("MasterNetworkController: Deinit")
    }
}

// MARK: - Control

extension MasterNetworkController: MasterNetworkControllable {
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
        networkModel.sessionId = UUID().uuidString
        listenerRestartAttempt = 0
        startListener()

        networkModel.browserManager = BrowserManager(serviceType: proxy ? .proxyClient : .master)
        networkModel.browserManager?.start()
        observeConnections()
    }

    private func startListener() {
        networkModel.listener = listnerBuilder(
            networkModel.name,
            networkModel.supporterTier,
            networkModel.isProxyHosting,
            networkModel.passcode,
            networkModel.sessionId,
            self
        )
        networkModel.listener?.startListening()
        // `listenerStatus` becomes `.running` only once `listenerReady()` fires for the
        // listener's real `.ready` event — see §5.22. Until then hosting reads as starting
        // (not "stopped"); a restart keeps showing `.restarting`. See CODE_AUDIT_18 §5.15.
        if networkModel.listenerStatus != .restarting {
            networkModel.listenerStatus = .starting
        }
        listenerStartedAt = ContinuousClock.now
    }

    /// Restarts hosting services that stopped while the app was not active, without dropping
    /// players that are still connected. See CODE_AUDIT_Join §5.3.
    func resumeAfterActivation() {
        guard networkModel.isStreaming else { return }
        if networkModel.listener == nil {
            listenerRestartTask?.cancel()
            listenerRestartTask = nil
            listenerRestartAttempt = 0
            startListener()
        }
        if let browser = networkModel.browserManager {
            if !browser.isBrowsing {
                browser.start()
            }
        } else {
            // Recreate a browser that was dropped while hosting, so returning players are
            // redialed again. See CODE_AUDIT_18 §5.14.
            networkModel.browserManager = BrowserManager(serviceType: networkModel.isProxyHosting ? .proxyClient : .master)
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
        listenerRestartTask?.cancel()
        listenerRestartTask = nil
        networkModel.listenerStatus = .stopped
        // Fire-and-forget: `resetConnections()` is synchronous (called from
        // the non-async `startStreaming`/`stopStreaming`), and clearing
        // pending entries has no ordering dependency on anything else here.
        Task { await connectionThrottle.clearAllPending() }
        // The receive loop holds each controller strongly, so dropping the reference never
        // reaches `deinit`; cancel explicitly or the peer stays connected and black-holed.
        // See CODE_AUDIT_16 §3.1.
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
        let previous = outboundChain
        let send = Task { @MainActor in
            await previous?.value
            // A nil encoding (encode failure) used to go out as a zero-length frame, which
            // the receiver treats as the peer closing the connection. See CODE_AUDIT_18 §3.15.
            guard let encodedData = await encodedOffMain(data) else {
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
        await delegate.masterReady(for: id)
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate.masterReceived(data: data, for: id, fileJournal: false)
    }
}

// MARK: - ListenerManagerDelegate

extension MasterNetworkController: ListenerManagerDelegate {
    /// Live connections a master accepts from its listener at once.
    static let maximumConnections = 32
    /// Reconnect dials in flight or connected at once. Kept apart from the inbound limit so
    /// advertisements from other devices can never use up the slots players join through.
    /// See CODE_AUDIT_Join §6.2.
    static let maximumOutboundDials = 8

    /// Connections the listener accepted (everything that is not one of our own dials).
    private var inboundConnectionCount: Int {
        networkModel.connections.count - browserConnectionEndpoints.count
    }

    /// A failed listener no longer ends hosting: connected players keep their connections and
    /// the listener is recreated with a growing pause, so new and reconnecting players can still
    /// join. If it keeps failing the status becomes `.failed` for the UI to show.
    /// See CODE_AUDIT_Join §5.3.
    /// The only point `listenerStatus` is set to `.running` from — derived from the
    /// listener's real `.ready` state, not assumed right after `startListener()` calls
    /// `startListening()`. See CODE_AUDIT_17 §5.22.
    @MainActor
    func listenerReady() async {
        guard networkModel.isStreaming else { return }
        networkModel.listenerStatus = .running
    }

    @MainActor
    func listenerWaiting(_ error: NWError) async {
        guard networkModel.isStreaming else { return }
        networkModel.listenerStatus = .waiting
    }

    @MainActor
    func listenerCancelled() async {
        guard networkModel.isStreaming else { return }
        Logger.networking.debug("MasterNetworkController: Listener stopped, scheduling restart")
        let staleListener = networkModel.listener
        networkModel.listener = nil
        staleListener?.stopListening()

        // A listener that ran for a while before failing is a new incident, not a retry storm.
        if let startedAt = listenerStartedAt, ContinuousClock.now - startedAt > Self.listenerHealthyDuration {
            listenerRestartAttempt = 0
        }
        guard listenerRestartAttempt < Self.listenerRestartDelays.count + Self.extraListenerRestartAttempts else {
            networkModel.listenerStatus = .failed
            return
        }
        let delay = Self.listenerRestartDelays[min(listenerRestartAttempt, Self.listenerRestartDelays.count - 1)]
        listenerRestartAttempt += 1
        networkModel.listenerStatus = .restarting
        listenerRestartTask?.cancel()
        listenerRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.networkModel.isStreaming, self.networkModel.listener == nil else { return }
            self.startListener()
        }
    }

    static let listenerRestartDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]
    /// Attempts made at the longest pause before giving up.
    static let extraListenerRestartAttempts = 4
    static let listenerHealthyDuration: Duration = .seconds(120)

    @MainActor
    func listenerNewConnection(_ connection: NWConnection) async {
        // A game has a handful of players; an unbounded connection table lets one
        // authenticated (or handshake-spamming) peer exhaust memory. See CODE_AUDIT_15 §6.1.
        guard inboundConnectionCount < Self.maximumConnections else {
            Logger.networking.debug("MasterNetworkController: Rejected connection, connection limit reached")
            connection.cancel()
            return
        }
        let generation = networkModel.connectionGeneration
        guard await connectionThrottle.shouldAllow(endpoint: connection.endpoint) else {
            Logger.networking.debug("MasterNetworkController: Rejected connection attempt from throttled source")
            connection.cancel()
            return
        }
        let id = UUID()
        await connectionThrottle.register(id: id, endpoint: connection.endpoint)
        // A reset during the suspensions above already cleared the pending bookkeeping; a
        // connection admitted now would have no owning listener. See CODE_AUDIT_16 §3.3.
        guard generation == networkModel.connectionGeneration,
              inboundConnectionCount < Self.maximumConnections else {
            await connectionThrottle.clear(id: id)
            connection.cancel()
            return
        }
        Logger.networking.debug("MasterNetworkController: New Connection")
        addNew(ConnectionController(id: id, connection: connection, delegate: self))
        enforceHandshakeDeadline(for: id)
    }

    /// Seconds an inbound connection may stay unauthenticated before it is dropped, so idle
    /// sockets cannot hold the pending-handshake slots. See CODE_AUDIT_16 §6.2.
    static let handshakeDeadline: Duration = .seconds(15)

    private func enforceHandshakeDeadline(for id: ConnectionController.ID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.handshakeDeadline)
            guard let self, await connectionThrottle.isPending(id: id) else { return }
            Logger.networking.debug("MasterNetworkController: Handshake deadline expired")
            guard let stale = networkModel.connections.first(where: { $0.id == id }) else { return }
            await stale.cancel()
        }
    }

    /// Convenience accessor used by tests to inject a connection directly.
    func newConnection(for nwConnection: NWConnection) async {
        await listenerNewConnection(nwConnection)
    }
}

// MARK: - Observe BrowserManager for Connections

extension MasterNetworkController {
    /// One stored `Observations` loop instead of re-arming `withObservationTracking` per
    /// change (two unstructured hops each, and the chain broke whenever an early return
    /// skipped the re-arm). See CODE_AUDIT_18 §3.21.
    func observeConnections() {
        guard let browser = networkModel.browserManager else { return }
        networkModel.observeConnectionsTask?.cancel()
        networkModel.observeConnectionsTask = Task { @MainActor [weak self] in
            for await games in Observations({ browser.games }) {
                guard let self, !Task.isCancelled,
                      self.networkModel.browserManager === browser else { return }
                self.refresh(games: games)
            }
        }
    }

    func checkForConnections() {
        guard networkModel.browserManager != nil else { return }
        let games = networkModel.browserManager?.games ?? []
        refresh(games: games)
    }

    func refresh(games: [BrowserGameModel]) {
        guard let manager = networkModel.browserManager, manager.isBrowsing else {
            // A browser inside its supervised restart pause is only briefly not browsing:
            // keep it (and its dialed connections) instead of dropping auto-redial for the
            // rest of the session. See CODE_AUDIT_18 §5.14.
            if networkModel.browserManager?.isSupervising == true { return }
            networkModel.browserManager = nil
            networkModel.browserConnections = []
            browserConnectionEndpoints = [:]
            return
        }
        // Only this session's own reconnect services are dialed: another group's players
        // advertise the same service type on the same network. See CODE_AUDIT_Join §5.2.
        let ownGames = games.filter { $0.sessionId == networkModel.sessionId }
        let endpoints = ownGames.map { manager.nwEndpoint(for: $0) }
        let advertisedEndpoints = Set(endpoints)
        networkModel.browserConnections.removeAll { !advertisedEndpoints.contains($0) }
        browserConnectionEndpoints = browserConnectionEndpoints.filter { advertisedEndpoints.contains($0.value) }
        for endpoint in redialTasks.keys where !advertisedEndpoints.contains(endpoint) {
            redialTasks.removeValue(forKey: endpoint)?.cancel()
            redialAttempts.removeValue(forKey: endpoint)
        }

        for endpoint in endpoints {
            // An endpoint waiting for its backoff is redialed by that timer, not immediately.
            if !networkModel.browserConnections.contains(endpoint), redialTasks[endpoint] == nil {
                connectToPlayer(endpoint: endpoint)
            }
        }
    }
}

private extension MasterNetworkController {
    func removeConnectionAndNotify(id: ConnectionController.ID) async {
        if removeConnection(id: id) {
            await delegate.masterLostPlayer(with: id)
        }
    }

    func removeConnection(id: ConnectionController.ID) -> Bool {
        guard networkModel.removeConnection(id: id) else { return false }

        networkModel.connectionStartTasks[id]?.cancel()
        networkModel.connectionStartTasks.removeValue(forKey: id)
        let wasEstablished = establishedConnectionIds.remove(id) != nil
        if let endpoint = browserConnectionEndpoints.removeValue(forKey: id),
           !browserConnectionEndpoints.values.contains(endpoint) {
            networkModel.browserConnections.removeAll { $0 == endpoint }
            if !wasEstablished {
                scheduleRedial(of: endpoint)
            }
        }
        return true
    }

    /// Retries a dial that failed before it connected, with a growing pause and a bounded number
    /// of attempts. Previously nothing retried it until an unrelated service came or went, and
    /// then every missing endpoint was redialed at once. See CODE_AUDIT_Join §5.4.
    func scheduleRedial(of endpoint: NWEndpoint) {
        guard networkModel.isStreaming else { return }
        let attempt = redialAttempts[endpoint, default: 0] + 1
        guard attempt <= Self.maximumRedialAttempts else { return }
        redialAttempts[endpoint] = attempt
        let seconds = min(2 << (attempt - 1), 30)
        redialTasks[endpoint]?.cancel()
        redialTasks[endpoint] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.redialTasks.removeValue(forKey: endpoint)
            guard self.networkModel.isStreaming, self.isAdvertised(endpoint) else { return }
            self.connectToPlayer(endpoint: endpoint)
        }
    }

    static let maximumRedialAttempts = 5

    func isAdvertised(_ endpoint: NWEndpoint) -> Bool {
        guard let manager = networkModel.browserManager else { return false }
        return manager.games.contains {
            $0.sessionId == networkModel.sessionId && manager.nwEndpoint(for: $0) == endpoint
        }
    }

    /// Cancels a dial that has not connected after `handshakeDeadline`, so a peer that accepts the
    /// connection and then stalls cannot hold its slot forever.
    func enforceDialDeadline(for id: ConnectionController.ID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.handshakeDeadline)
            guard let self, !establishedConnectionIds.contains(id),
                  let stale = networkModel.connections.first(where: { $0.id == id }) else { return }
            Logger.networking.debug("MasterNetworkController: Dial deadline expired")
            await stale.cancel()
        }
    }

    func addNew(_ connection: any ConnectionControllable) {
        networkModel.connections.append(connection)
        let id = connection.id
        networkModel.connectionStartTasks[id]?.cancel()
        networkModel.connectionStartTasks[id] = Task { @MainActor [weak self] in
            await connection.startConnection()
            self?.networkModel.connectionStartTasks.removeValue(forKey: id)
        }
    }

}

extension MasterNetworkController {
    func connectToPlayer(endpoint: NWEndpoint) {
        guard !networkModel.browserConnections.contains(endpoint) else { return }
        guard browserConnectionEndpoints.count < Self.maximumOutboundDials else {
            Logger.networking.debug("MasterNetworkController: Not dialing, outbound dial limit reached")
            return
        }
        networkModel.browserConnections.append(endpoint)
        // Reuses the same passcode this session's listener was started with —
        // this is a reconnect dial-out to a player already admitted earlier
        // in the session, not a new join, so no new code entry is needed.
        let connection = browserConnectionBuilder(endpoint, networkModel.passcode, self)
        browserConnectionEndpoints[connection.id] = endpoint
        addNew(connection)
        enforceDialDeadline(for: connection.id)
    }
}
