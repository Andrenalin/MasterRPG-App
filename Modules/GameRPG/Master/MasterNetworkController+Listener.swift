// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

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

        let scheduled = listenerRestarts.schedule { [weak self] in
            guard let self, self.networkModel.isStreaming, self.networkModel.listener == nil else { return }
            self.startListener()
        }
        networkModel.listenerStatus = scheduled ? .restarting : .failed
    }

    @MainActor
    func listenerNewConnection(_ connection: GameConnection) async {
        // A game has a handful of players; an unbounded connection table lets one
        // authenticated (or handshake-spamming) peer exhaust memory. See CODE_AUDIT_15 §6.1.
        guard inboundConnectionCount < Self.maximumConnections else {
            // Returning drops the only reference, which closes the connection.
            Logger.networking.debug("MasterNetworkController: Rejected connection, connection limit reached")
            return
        }
        let generation = networkModel.connectionGeneration
        guard await connectionThrottle.shouldAllow(endpoint: connection.remoteEndpoint) else {
            Logger.networking.debug("MasterNetworkController: Rejected connection attempt from throttled source")
            return
        }
        let id = UUID()
        await connectionThrottle.register(id: id, endpoint: connection.remoteEndpoint)
        // A reset during the suspensions above already cleared the pending bookkeeping; a
        // connection admitted now would have no owning listener. See CODE_AUDIT_16 §3.3.
        guard generation == networkModel.connectionGeneration,
              inboundConnectionCount < Self.maximumConnections else {
            await connectionThrottle.clear(id: id)
            return
        }
        Logger.networking.debug("MasterNetworkController: New Connection")
        addNew(ConnectionController(id: id, connection: connection, delegate: self))
        enforceHandshakeDeadline(for: id)
    }

    /// Drops an inbound connection still unauthenticated after `GameLimits.handshakeDeadline`, so
    /// idle sockets cannot hold the pending-handshake slots. See CODE_AUDIT_16 §6.2.
    private func enforceHandshakeDeadline(for id: ConnectionController.ID) {
        startDeadline(for: id) { controller in
            guard await controller.connectionThrottle.isPending(id: id) else { return }
            Logger.networking.debug("MasterNetworkController: Handshake deadline expired")
            await controller.cancelConnection(id: id)
        }
    }

    /// Convenience accessor used by tests to inject a connection directly.
    func newConnection(for connection: GameConnection) async {
        await listenerNewConnection(connection)
    }
}
