// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

// MARK: - ListenerManagerDelegate

extension PlayerNetworkController: ListenerManagerDelegate {
    @MainActor
    func listenerReady() async {}

    /// The fallback listener failed. While the player is still waiting for its master it is
    /// recreated after a pause; only when that keeps failing (or there is nothing to wait for)
    /// does the controller stop. See CODE_AUDIT_Join §5.3.
    @MainActor
    func listenerCancelled() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener cancelled")
        networkModel.reset(listener: nil)
        let scheduled = isAwaitingReconnect && networkModel.playerConnectionId != nil &&
            listenerRestarts.schedule { [weak self] in
                guard let self, self.isAwaitingReconnect, self.networkModel.listener == nil else { return }
                await self.startPlayerServer()
            }
        if !scheduled {
            await stop()
        }
    }

    @MainActor
    func listenerNewConnection(_ connection: GameConnection) async {
        // Returning without keeping `connection` closes it.
        guard await connectionThrottle.shouldAllow(endpoint: connection.remoteEndpoint) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Rejected connection attempt from throttled source")
            return
        }
        // Only a lost player takes a connection, and only one at a time. The listener stays up
        // either way: it is retired when a connection authenticates, so one unauthenticated or
        // foreign connection can no longer end the reconnect. See CODE_AUDIT_Join §5.1.
        //
        // An attempt that is still unauthenticated after the grace period gives way to a newer
        // connection and counts as a failure of its source: a stalled peer used to keep every
        // other connection, the master's among them, out for the whole handshake deadline,
        // while the master gives up after a few dials. See CODE_AUDIT_21 §6.2.
        if let stalledId = stalledReconnectAttemptId() {
            Logger.playerNetworkController.debug("PlayerNetworkController: Replacing a stalled reconnect attempt")
            let generation = stopGeneration
            await connectionThrottle.resolve(id: stalledId, succeeded: false)
            // A stop during that suspension ended the reconnect.
            guard generation == stopGeneration, isAwaitingReconnect else { return }
        } else {
            guard networkModel.connectionState == .lost else {
                Logger.playerNetworkController.debug("PlayerNetworkController: Dropping connection attempt outside a reconnect")
                return
            }
        }
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection")
        networkModel.reset(isConnected: false)
        networkModel.reset(state: .notReady)
        await restart(connection: connection)
    }
}

private extension PlayerNetworkController {
    /// The reconnect attempt that has waited for its handshake longer than the grace period.
    func stalledReconnectAttemptId() -> ConnectionController.ID? {
        guard isAwaitingReconnect, networkModel.connectionState == .notReady,
              let id = networkModel.connectionController?.id,
              let start = reconnectAttemptStart,
              ContinuousClock.now - start >= reconnectHandshakeGrace else { return nil }
        return id
    }
}
