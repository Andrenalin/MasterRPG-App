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
    let listnerBuilder: @MainActor @Sendable (String, SupporterTier, Bool, String, any ListenerManagerDelegate) -> any ListenerManaging
    let browserConnectionBuilder: @MainActor @Sendable (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable
    let networkModel: MasterNetworkNodel
    private var browserConnectionEndpoints: [ConnectionController.ID: NWEndpoint] = [:]
    // See CODE_AUDIT §6.1: throttles repeated bad-passcode attempts on the inbound
    // listener. connectToPlayer's outbound reconnect dial-outs are never throttled —
    // this device is the one connecting there, not receiving an unknown attempt.
    private let connectionThrottle = ConnectionAttemptThrottle()
    private var pendingConnectionSources: [ConnectionController.ID: String] = [:]

    static func gameListnerBuilder() -> @MainActor @Sendable (String, SupporterTier, Bool, String, any ListenerManagerDelegate) -> any ListenerManaging {
        return { name, supporterTier, proxy, passcode, delegate in
            let manager = ListenerManager(name: name, supporterTier: supporterTier, serviceType: proxy ? .proxyServer : .player, passcode: passcode)
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
        listnerBuilder: @MainActor @Sendable @escaping (String, SupporterTier, Bool, String, any ListenerManagerDelegate) -> any ListenerManaging,
        browserConnectionBuilder: @MainActor @Sendable @escaping (NWEndpoint, String, any ConnectionControllerDelegate) -> any ConnectionControllable = MasterNetworkController.gameBrowserConnectionBuilder()
    ) {
        self.networkModel = MasterNetworkNodel(name: name)
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

        resetConntections()
        networkModel.isStreaming = true
        networkModel.passcode = passcode

        networkModel.listener = listnerBuilder(networkModel.name, networkModel.supporterTier, false, passcode, self)
        networkModel.listener?.startListening()

        networkModel.browserManager = BrowserManager(serviceType: .master)
        networkModel.browserManager?.start()
        observeConnections()
    }

    func startProxyStreaming(passcode: String) {
        Logger.networking.debug("MasterNetworkController: Start Proxy Streaming")

        resetConntections()
        networkModel.isStreaming = true
        networkModel.passcode = passcode

        networkModel.listener = listnerBuilder(networkModel.name, networkModel.supporterTier, true, passcode, self)
        networkModel.listener?.startListening()

        networkModel.browserManager = BrowserManager(serviceType: .proxyClient)
        networkModel.browserManager?.start()
        observeConnections()
    }

    func stopStreaming() {
        Logger.networking.debug("MasterNetworkController: Stop Streaming")

        resetConntections()
        networkModel.isStreaming = false
    }

    func toggleStreaming(passcode: String) {
        if networkModel.isStreaming {
            stopStreaming()
        } else {
            startStreaming(passcode: passcode)
        }
    }

    private func resetConntections() {
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
        pendingConnectionSources = [:]
        networkModel.connections = []
    }
}

// MARK: - Send

extension MasterNetworkController {
    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        guard let connection = networkModel.connections.first(where: { $0.id == id }) else { return false }
        let encodedData = data?.encodeData()
        await connection.response(type: .gameData, encodedContent: encodedData)
        return true
    }

    func sendResponse(data: MessageMapper?) async {
        let connections = networkModel.connections
        guard !connections.isEmpty else { return }
        let encodedData = data?.encodeData()
        await withDiscardingTaskGroup { group in
            for connection in connections {
                group.addTask {
                    await connection.response(type: .gameData, encodedContent: encodedData)
                }
            }
        }
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        let connections = networkModel.connections.filter { $0.id != except }
        guard !connections.isEmpty else { return }
        let encodedData = data?.encodeData()
        await withDiscardingTaskGroup { group in
            for connection in connections {
                group.addTask {
                    await connection.response(type: .gameData, encodedContent: encodedData)
                }
            }
        }
    }
}

// MARK: - MasterConnectionDelegate

extension MasterNetworkController: ConnectionControllerDelegate {
    @MainActor
    func failed(with error: String?, for id: ConnectionController.ID) async {
        if let source = pendingConnectionSources.removeValue(forKey: id) {
            await connectionThrottle.recordFailure(source: source)
        }
        await removeConnectionAndNotify(id: id)
    }

    /// A clean cancellation (peer disconnected, backgrounded, network drop) is
    /// not a bad-passcode attempt, unlike `failed(with:for:)` above — clear its
    /// pending entry without penalizing the source.
    @MainActor
    func lostConnection(for id: ConnectionController.ID) async {
        pendingConnectionSources.removeValue(forKey: id)
        await removeConnectionAndNotify(id: id)
    }

    @MainActor
    func readyConnection(for id: ConnectionController.ID) async {
        if let source = pendingConnectionSources.removeValue(forKey: id) {
            await connectionThrottle.recordSuccess(source: source)
        }
        await delegate.masterReady(for: id)
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate.masterReceived(data: data, for: id, fileJournal: false)
    }
}

// MARK: - ListenerManagerDelegate

extension MasterNetworkController: ListenerManagerDelegate {
    func listenerCancelled() async {
        await stopStreaming()
    }

    @MainActor
    func listenerNewConnection(_ connection: NWConnection) async {
        let source = connection.endpoint.throttleSourceKey
        if let source, await !connectionThrottle.shouldAllow(source: source) {
            Logger.networking.debug("MasterNetworkController: Rejected connection attempt from throttled source")
            connection.cancel()
            return
        }
        Logger.networking.debug("MasterNetworkController: New Connection")
        let id = UUID()
        if let source {
            pendingConnectionSources[id] = source
        }
        addNew(ConnectionController(id: id, connection: connection, delegate: self))
    }

    /// Convenience accessor used by tests to inject a connection directly.
    func newConnection(for nwConnection: NWConnection) async {
        await listenerNewConnection(nwConnection)
    }
}

// MARK: - Observe BrowserManager for Connections

extension MasterNetworkController {
    func observeConnections() {
        guard networkModel.browserManager != nil else { return }
        _ = withObservationTracking {
            networkModel.browserManager?.games
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleConnectionCheck()
            }
        }
    }

    private func scheduleConnectionCheck() {
        networkModel.observeConnectionsTask?.cancel()
        networkModel.observeConnectionsTask = Task { @MainActor [weak self] in
            self?.checkForConnections()
        }
    }

    func checkForConnections() {
        guard networkModel.browserManager != nil else { return }
        let games = networkModel.browserManager?.games ?? []
        refresh(games: games)
        observeConnections()
    }

    func refresh(games: [BrowserGameModel]) {
        guard let manager = networkModel.browserManager, manager.isBrowsing else {
            networkModel.browserManager = nil
            networkModel.browserConnections = []
            browserConnectionEndpoints = [:]
            return
        }
        let endpoints = games.map { manager.nwEndpoint(for: $0) }
        let advertisedEndpoints = Set(endpoints)
        networkModel.browserConnections.removeAll { !advertisedEndpoints.contains($0) }
        browserConnectionEndpoints = browserConnectionEndpoints.filter { advertisedEndpoints.contains($0.value) }

        for endpoint in endpoints {
            if !networkModel.browserConnections.contains(endpoint) {
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
        if let endpoint = browserConnectionEndpoints.removeValue(forKey: id),
           !browserConnectionEndpoints.values.contains(endpoint) {
            networkModel.browserConnections.removeAll { $0 == endpoint }
        }
        return true
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
        networkModel.browserConnections.append(endpoint)
        // Reuses the same passcode this session's listener was started with —
        // this is a reconnect dial-out to a player already admitted earlier
        // in the session, not a new join, so no new code entry is needed.
        let connection = browserConnectionBuilder(endpoint, networkModel.passcode, self)
        browserConnectionEndpoints[connection.id] = endpoint
        addNew(connection)
    }
}
