// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

final class MasterNetworkController: Sendable {
    // Set once in init, never reassigned. Swift runtime zeroes weak refs atomically — safe for concurrent reads.
    nonisolated(unsafe) private weak var delegate: (any MasterNetworkControllerDelegate)?
    let listnerBuilder: @Sendable (String, Bool, ListenerControllerDelegate) -> ListenerControllable
    let networkModel: MasterNetworkNodel

    static func gameListnerBuilder() -> @Sendable (String, Bool, ListenerControllerDelegate) -> ListenerControllable {
        return { name, proxy, delegate in
            if proxy {
                return ListenerController(proxy: name, delegate: delegate)
            } else {
                return ListenerController(master: name, delegate: delegate)
            }
        }
    }

    @MainActor
    init(name: String, delegate: MasterNetworkControllerDelegate? = nil, listnerBuilder: @Sendable @escaping (String, Bool, ListenerControllerDelegate) -> ListenerControllable) {
        self.networkModel = MasterNetworkNodel(name: name)
        self.delegate = delegate
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
        networkModel.browserManager?.stop()
        networkModel.browserManager = nil
        networkModel.listener?.stopListnening()
        networkModel.listener = nil
        networkModel.browserConnections = []
        networkModel.connections = []
    }
}

// MARK: - Send

extension MasterNetworkController {
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async {
        await networkModel.connections.first { $0.id == id }?.sendResponse(data: data)
    }

    func sendResponse(data: MessageMapper?) async {
        await networkModel.connections.forEach { $0.sendResponse(data: data) }
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        for connection in await networkModel.connections {
            if connection.id != except {
                connection.sendResponse(data: data)
            }
        }
    }
}

// MARK: - MasterConnectionDelegate

extension MasterNetworkController: ConnectionControllerDelegate {
    func failed(with error: String?, for id: ConnectionController.ID) async {
        if await networkModel.removeConnection(id: id) {
            await delegate?.masterLostPlayer(with: id)
        }
    }

    func lostConnection(for id: ConnectionController.ID) async {
        await failed(with: "Player disconnected", for: id)
    }

    func readyConnection(for id: ConnectionController.ID) async {
        await delegate?.masterReady(for: id)
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate?.masterReceived(data: data, for: id, fileJournal: false)
    }
}

// MARK: - GameListnerDelegate

extension MasterNetworkController: ListenerControllerDelegate {
    func cancelled() async {
        await stopStreaming()
    }

    func newConnection(for nwConnection: NWConnection) async {
        Logger.networking.debug("MasterNetworkController: New Connection \(nwConnection.debugDescription)")
        await addNew(ConnectionController(id: UUID(), connection: nwConnection, delegate: self))
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
            Task { @concurrent in
                await self?.checkForConnections()
            }
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
    @MainActor func addNew(_ connection: ConnectionController) {
        networkModel.connections.append(connection)
        connection.startConnection()
    }

    @MainActor func connectToPlayer(endpoint: NWEndpoint) {
        addNew(ConnectionController(id: UUID(), endpoint: endpoint, delegate: self))
    }
}
