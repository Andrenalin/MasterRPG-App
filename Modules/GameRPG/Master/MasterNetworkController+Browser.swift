// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

// MARK: - Observe BrowserManager for Connections

extension MasterNetworkController {
    /// One stored `Observations` loop instead of re-arming `withObservationTracking` per
    /// change (two unstructured hops each, and the chain broke whenever an early return
    /// skipped the re-arm). See CODE_AUDIT_18 §3.21.
    func observeConnections() {
        guard let browser = networkModel.browserManager else { return }
        networkModel.observeConnectionsTask?.cancel()
        // The sequence and the task hold the browser weakly, and the sequence ends with it: a
        // controller released without `stopStreaming()` must not keep the browser and its
        // Bonjour browse alive. See CODE_AUDIT_20 §3.5.
        let changes = Observations<[BrowserGameModel], Never>.untilFinished { [weak browser] in
            guard let browser else { return .finish }
            return .next(browser.games)
        }
        networkModel.observeConnectionsTask = Task { @MainActor [weak self, weak browser] in
            for await games in changes {
                guard let self, let browser, !Task.isCancelled,
                      self.networkModel.browserManager === browser else { return }
                self.refresh(games: games)
            }
        }
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
        for game in games where game.sessionId != networkModel.sessionId {
            Logger.networking.debug("MasterNetworkController: Not redialing \(game.endpointName, privacy: .private), session \(game.sessionId == nil ? "missing" : "different", privacy: .public)")
        }
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

extension MasterNetworkController {
    func removeConnectionAndNotify(id: ConnectionController.ID) async {
        if removeConnection(id: id) {
            await delegate?.masterLostPlayer(with: id)
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

    /// Cancels a dial that has not connected after `GameLimits.handshakeDeadline`, so a peer that accepts the
    /// connection and then stalls cannot hold its slot forever.
    func enforceDialDeadline(for id: ConnectionController.ID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: GameLimits.handshakeDeadline)
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
