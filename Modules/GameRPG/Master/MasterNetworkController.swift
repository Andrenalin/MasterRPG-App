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

final class MasterNetworkController: Sendable {
    private let delegate: MasterNetworkControllerDelegateBox
    let listnerBuilder: @MainActor @Sendable (String, Bool, any ListenerManagerDelegate) -> any ListenerManaging
    let networkModel: MasterNetworkNodel

    static func gameListnerBuilder() -> @MainActor @Sendable (String, Bool, any ListenerManagerDelegate) -> any ListenerManaging {
        return { name, proxy, delegate in
            let manager = ListenerManager(name: name, serviceType: proxy ? .proxyServer : .player)
            manager.delegate = delegate
            return manager
        }
    }

    @MainActor
    init(name: String, delegate: MasterNetworkControllerDelegate? = nil, listnerBuilder: @MainActor @Sendable @escaping (String, Bool, any ListenerManagerDelegate) -> any ListenerManaging) {
        self.networkModel = MasterNetworkNodel(name: name)
        self.delegate = MasterNetworkControllerDelegateBox(delegate)
        self.listnerBuilder = listnerBuilder
        Logger.networking.debug("MasterNetworkController: Init")
    }

    deinit {
        Logger.networking.debug("MasterNetworkController: Deinit")
    }
}

// MARK: - Control

extension MasterNetworkController: MasterNetworkControllable {
    @MainActor
    func startStreaming() {
        Logger.networking.debug("MasterNetworkController: Start Streaming")

        resetConntections()
        networkModel.isStreaming = true

        networkModel.listener = listnerBuilder(networkModel.name, false, self)
        networkModel.listener?.startListening()

        networkModel.browserManager = BrowserManager(serviceType: .master)
        networkModel.browserManager?.start()
        observeConnections()
    }

    @MainActor
    func startProxyStreaming() {
        Logger.networking.debug("MasterNetworkController: Start Proxy Streaming")

        resetConntections()
        networkModel.isStreaming = true

        networkModel.listener = listnerBuilder(networkModel.name, true, self)
        networkModel.listener?.startListening()

        networkModel.browserManager = BrowserManager(serviceType: .proxyClient)
        networkModel.browserManager?.start()
        observeConnections()
    }

    @MainActor
    func stopStreaming() {
        Logger.networking.debug("MasterNetworkController: Stop Streaming")

        resetConntections()
        networkModel.isStreaming = false
    }

    @MainActor
    func toggleStreaming() {
        if networkModel.isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }

    @MainActor
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
        networkModel.connections = []
    }
}

// MARK: - Send

extension MasterNetworkController {
    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        guard let connection = await networkModel.connections.first(where: { $0.id == id }) else { return false }
        let encodedData = data?.encodeData()
        await connection.response(type: .gameData, encodedContent: encodedData)
        return true
    }

    func sendResponse(data: MessageMapper?) async {
        let connections = await networkModel.connections
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
        let connections = await networkModel.connections.filter { $0.id != except }
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
    func failed(with error: String?, for id: ConnectionController.ID) async {
        if await networkModel.removeConnection(id: id) {
            await delegate.masterLostPlayer(with: id)
        }
    }

    func lostConnection(for id: ConnectionController.ID) async {
        await failed(with: "Player disconnected", for: id)
    }

    func readyConnection(for id: ConnectionController.ID) async {
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

    func listenerNewConnection(_ connection: NWConnection) async {
        Logger.networking.debug("MasterNetworkController: New Connection")
        await addNew(ConnectionController(id: UUID(), connection: connection, delegate: self))
    }

    /// Convenience accessor used by tests to inject a connection directly.
    func newConnection(for nwConnection: NWConnection) async {
        await listenerNewConnection(nwConnection)
    }
}

// MARK: - Observe BrowserManager for Connections

extension MasterNetworkController {
    @MainActor
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

    @MainActor
    private func scheduleConnectionCheck() {
        networkModel.observeConnectionsTask?.cancel()
        networkModel.observeConnectionsTask = Task { @MainActor [weak self] in
            self?.checkForConnections()
        }
    }

    @MainActor
    func checkForConnections() {
        guard networkModel.browserManager != nil else { return }
        let games = networkModel.browserManager?.games ?? []
        refresh(games: games)
        observeConnections()
    }

    @MainActor func refresh(games: [BrowserGameModel]) {
        guard let manager = networkModel.browserManager, manager.isBrowsing else {
            networkModel.browserManager = nil
            networkModel.browserConnections = []
            return
        }
        for game in games {
            let endpoint = manager.nwEndpoint(for: game)
            if !networkModel.browserConnections.contains(endpoint) {
                networkModel.browserConnections.append(endpoint)
                connectToPlayer(endpoint: endpoint)
            }
        }
    }
}

private extension MasterNetworkController {
    @MainActor func addNew(_ connection: any ConnectionControllable) {
        networkModel.connections.append(connection)
        let id = connection.id
        networkModel.connectionStartTasks[id]?.cancel()
        networkModel.connectionStartTasks[id] = Task { @MainActor [weak self] in
            await connection.startConnection()
            self?.networkModel.connectionStartTasks.removeValue(forKey: id)
        }
    }

    @MainActor func connectToPlayer(endpoint: NWEndpoint) {
        addNew(ConnectionController(id: UUID(), endpoint: endpoint, delegate: self))
    }
}
