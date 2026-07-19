// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI

// MARK: - Direct-mode delegate protocols

protocol MasterNetworkStoreDelegate: Sendable & AnyObject {
    /// Authenticates an inbound transport envelope before the network bridge
    /// relays it to another transport or any sibling LAN connection.
    func accepts(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool
    func ready(for origin: GameMessageOrigin) async
    func received(_ model: GameNetworkModel, origin: GameMessageOrigin) async
    func receivedFile(_ model: GameNetworkModel) async
    func lostPlayer(for connectionId: ConnectionController.ID) async
}

extension MasterNetworkStoreDelegate {
    func ready(for connectionId: ConnectionController.ID) async {
        await ready(for: .direct(connectionId))
    }

    /// Compatibility convenience for direct-network callers. Keeping only the
    /// origin-aware method as a protocol requirement avoids mutually recursive
    /// default implementations when a conformer accidentally implements neither.
    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await received(model, origin: .direct(connectionId))
    }
}

protocol PlayerNetworkStoreDelegate: Sendable & AnyObject {
    func lostConnection() async
    func ready() async
    func received(_ model: GameNetworkModel) async
    func receivedFile(_ model: GameNetworkModel) async
    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async
    func receivedSharePlayFile(_ model: GameNetworkModel) async
    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async
    /// Performs side-effect-free logical session/roster validation before the
    /// transport layer pins a peer participant to the claimed player sender.
    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool
    /// Returns true only for a valid small peer event whose logical player is
    /// not present in the current authoritative roster yet. The transport may
    /// retain it until one subsequent accepted master-state update.
    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool
    /// Confirms that a complete master-state envelope was applied (or already
    /// represents the current state), allowing one batch of deferred peer
    /// events to be revalidated against the resulting roster.
    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool
    /// Authenticates and pins a complete master Journal admission without
    /// routing its data-less control packet through presentation handlers.
    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool
    /// Prevents session-visible Journal repairs for another logical player from
    /// occupying this player's bounded anonymous-callback queue.
    func isLocalSharePlayTarget(_ targetId: UUID?) async -> Bool
    /// Confirms that PlayerController accepted and pinned the physically
    /// attributed master. That participant may legitimately relay several LAN
    /// player identities into SharePlay while ordinary participants may not.
    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool
    /// Notifies a player that one physical GroupSession participant left. The
    /// player uses this to release a master-source binding only when that exact
    /// participant was the authenticated master.
    func sharePlayParticipantLeft(id: UUID) async
}

extension PlayerNetworkStoreDelegate {
    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await received(model)
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        await receivedFile(model)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        await receivedSharePlayFile(model)
    }

    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        model.sender.role == .player && model.effectiveAudience == .group
    }

    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool { false }

    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool { false }

    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool { false }

    func isLocalSharePlayTarget(_ targetId: UUID?) async -> Bool { true }

    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool { false }

    func sharePlayParticipantLeft(id: UUID) async {}
}

// MARK: - Proxy-mode delegate protocols

protocol MasterNetworkProxyControllerDelegate: Sendable & AnyObject {
    func lostProxy(for connectionId: ConnectionController.ID) async
    func readyProxy(for connectionId: ConnectionController.ID) async
    func receivedServerProxy(_ model: GameNetworkModel, connectionId: ConnectionController.ID) async
}

extension MasterNetworkProxyControllerDelegate {
    func lostProxy(for connectionId: ConnectionController.ID) async {}
}

protocol PlayerNetworkProxyControllerDelegate: Sendable & AnyObject {
    func lostProxyConnection() async
    func readyProxy() async
    func receivedProxy(_ model: GameNetworkModel) async
}

// MARK: - Model

@MainActor
final class GameNetworkControllerModel {
    let name: String
    var isSetup: Bool = false
    var hasLocalPlayer = false

    private(set) var masterStore: (any MasterNetworkControllable)?
    private(set) var playerStore: (any PlayerNetworkControllable)?

    init(name: String) {
        self.name = name
    }

    func setControllers(master: any MasterNetworkControllable, player: any PlayerNetworkControllable) {
        masterStore = master
        playerStore = player
    }

    func didSetup() { isSetup = true }

    func setLocalPlayers(to hasPlayers: Bool) { hasLocalPlayer = hasPlayers }

    // MARK: Direct-mode delegates

    var masterDelegate: (any MasterNetworkStoreDelegate)? { _masterDelegate }
    var playerDelegate: (any PlayerNetworkStoreDelegate)? { _playerDelegate }

    func setMasterDelegate(_ delegate: any MasterNetworkStoreDelegate) { _masterDelegate = delegate }
    func setPlayerDelegate(_ delegate: any PlayerNetworkStoreDelegate) { _playerDelegate = delegate }

    private weak var _masterDelegate: (any MasterNetworkStoreDelegate)?
    private weak var _playerDelegate: (any PlayerNetworkStoreDelegate)?

    // MARK: Proxy-mode delegates

    var masterProxyDelegate: (any MasterNetworkProxyControllerDelegate)? { _masterProxyDelegate }
    var playerProxyDelegate: (any PlayerNetworkProxyControllerDelegate)? { _playerProxyDelegate }

    func setProxyMasterDelegate(_ delegate: any MasterNetworkProxyControllerDelegate) { _masterProxyDelegate = delegate }
    func setProxyPlayerDelegate(_ delegate: any PlayerNetworkProxyControllerDelegate) { _playerProxyDelegate = delegate }

    private weak var _masterProxyDelegate: (any MasterNetworkProxyControllerDelegate)?
    private weak var _playerProxyDelegate: (any PlayerNetworkProxyControllerDelegate)?
}
