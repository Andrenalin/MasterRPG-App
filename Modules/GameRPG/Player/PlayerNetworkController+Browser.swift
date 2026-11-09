// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

// MARK: - Observe BrowserManager for Lost Connection

extension PlayerNetworkController {
    /// One stored `Observations` loop instead of re-arming `withObservationTracking` per
    /// change. It delivers every change for the task's lifetime, so a removal landing while
    /// an earlier batch is still being torn down is not missed. See CODE_AUDIT_18 §3.21.
    func observeRemovedConnection() {
        guard networkModel.model != nil else { return }
        let browser = browserManager
        networkModel.observeRemovalTask?.cancel()
        // The sequence holds the browser weakly and ends with it, so a controller released
        // without `stop()` cannot keep the browser and its Bonjour browse alive.
        // See CODE_AUDIT_20 §3.5.
        let changes = Observations<[BrowserGameModel], Never>.untilFinished { [weak browser] in
            guard let browser else { return .finish }
            return .next(browser.removed)
        }
        networkModel.observeRemovalTask = Task { @MainActor [weak self] in
            for await removed in changes {
                guard let self, !Task.isCancelled else { return }
                // `takeRemoved()` below empties the list, which is itself a change.
                guard !removed.isEmpty else { continue }
                await self.checkForRemoval()
            }
        }
    }

    func checkForRemoval() async {
        guard networkModel.model != nil else { return }
        // Re-arm `withObservationTracking` before processing the current
        // batch, not after. `onChange` fires once and must be re-registered
        // before the next mutation to be seen at all; the async teardown
        // below (`removedConnection` → `lostConnection` → several actor hops
        // and `stop()`'s own connection teardown) can take long enough that a
        // second Bonjour-removal change lands while still in flight — arming
        // late meant that change was missed until some later, unrelated
        // mutation happened to re-trigger observation. A second
        // `checkForRemoval()` scheduled by that re-registration racing this
        // one's own loop is safe: `lostConnection(for:)` is already
        // idempotent via `markLostIfCurrent`. See CODE_AUDIT_Reconnect §3.5.
        let removedGames = browserManager.takeRemoved()
        for game in removedGames {
            let endpoint = browserManager.nwEndpoint(for: game)
            await removedConnection(endpoint: endpoint)
        }
    }

    func removedConnection(endpoint: NWEndpoint) async {
        guard let model = networkModel.model else { return }
        Logger.playerNetworkController.debug("PlayerNetworkController: RemovedConnection \(endpoint.debugDescription, privacy: .private)")
        if model.endpoint == endpoint {
            guard let id = networkModel.connectionController?.id else { return }
            await lostConnection(for: id)
        }
    }
}
