// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI

// MARK: - Direct-mode delegate protocols

// All four delegate protocols below are @MainActor: their witnesses
// (MasterController/PlayerController) are @MainActor classes, and under this
// project's SWIFT_APPROACHABLE_CONCURRENCY = YES setting, an async witness of
// a *nonisolated* protocol requirement becomes `nonisolated(nonsending)` —
// it inherits whichever actor the *caller* happens to be on (the LAN path
// calls in from the ConnectionController actor), not the conforming type's
// own isolation. That turned what reads as one atomic @MainActor block into
// a sequence of independently-interleavable hops. Declaring the protocol
// requirements @MainActor makes the whole call one guaranteed atomic hop
// instead. See CODE_AUDIT_Game §3.1.
@MainActor
protocol MasterNetworkStoreDelegate: Sendable & AnyObject {
    /// Authenticates an inbound transport envelope before the network bridge
    /// relays it to another transport or any sibling LAN connection.
    func accepts(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool
    func ready(for origin: GameMessageOrigin) async
    func received(_ model: GameNetworkModel, origin: GameMessageOrigin) async
    func receivedFile(_ model: GameNetworkModel) async
    func lostPlayer(for connectionId: ConnectionController.ID) async
    /// Whether a player's group event may be relayed to the other players: the master checks the
    /// event before it passes it on, so an implausible, repeated or disabled one is not
    /// multiplied to every device. See CODE_AUDIT_23 §6.4.
    func mayRelay(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool
    /// A peer runs another version of the app. See CODE_AUDIT_Game_Shareplay §5.9.
    func incompatibleVersion(_ mismatch: GameVersionMismatch) async
}

extension MasterNetworkStoreDelegate {
    func mayRelay(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool { true }

    func incompatibleVersion(_ mismatch: GameVersionMismatch) async {}

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

@MainActor
protocol PlayerNetworkStoreDelegate: Sendable & AnyObject {
    func lostConnection() async
    func ready() async
    func received(_ model: GameNetworkModel) async
    func receivedFile(_ model: GameNetworkModel) async
    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async
    func receivedSharePlayFile(_ model: GameNetworkModel) async
    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async
    /// The download of the file `model` names started, is running, ended or was dropped (`nil`).
    func sharePlayTransferChanged(_ status: ItemTransferStatus?, for model: GameNetworkModel)
    /// Whether this device already holds the file `model` names, in that version, so the
    /// Journal's copy of it need not be downloaded.
    func sharePlayHoldsFile(_ model: GameNetworkModel) async -> Bool
    /// Whether this SharePlay participant is the one the game master's messages come from. The
    /// 3D table ranks seats without the master, and the master relays its local-network players
    /// into SharePlay under its own participant.
    func isSharePlayMasterParticipant(id: UUID) async -> Bool
    /// Notifies a player that one physical GroupSession participant left.
    func sharePlayParticipantLeft(id: UUID) async
    /// The master or another peer runs another version of the app. See
    /// CODE_AUDIT_Game_Shareplay §5.9.
    func incompatibleVersion(_ mismatch: GameVersionMismatch) async
}

extension PlayerNetworkStoreDelegate {
    func incompatibleVersion(_ mismatch: GameVersionMismatch) async {}

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await received(model)
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        await receivedFile(model)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {}

    func sharePlayTransferChanged(_ status: ItemTransferStatus?, for model: GameNetworkModel) {}

    func sharePlayHoldsFile(_ model: GameNetworkModel) async -> Bool { false }

    func isSharePlayMasterParticipant(id: UUID) async -> Bool { false }

    func sharePlayParticipantLeft(id: UUID) async {}
}

// MARK: - Proxy-mode delegate protocols

@MainActor
protocol MasterNetworkProxyControllerDelegate: Sendable & AnyObject {
    func lostProxy(for connectionId: ConnectionController.ID) async
    func readyProxy(for connectionId: ConnectionController.ID) async
    func receivedServerProxy(_ model: GameNetworkModel, connectionId: ConnectionController.ID) async
}

extension MasterNetworkProxyControllerDelegate {
    func lostProxy(for connectionId: ConnectionController.ID) async {}
}

@MainActor
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
    /// Which connection or SharePlay participant speaks for which player.
    var playerRoutes = GamePlayerRoutes()
    /// The connections that were already told this device cannot read them, and the mismatches
    /// already shown: each is said once, not for every message of a peer that keeps sending.
    private var versionNoticeConnectionIds: Set<UUID> = []
    private var hasSentVersionNotice = false
    private var reportedMismatches: Set<GameVersionMismatch> = []

    /// Whether the notice goes to `connectionId` now (once per connection).
    func claimVersionNotice(for connectionId: UUID) -> Bool {
        versionNoticeConnectionIds.insert(connectionId).inserted
    }

    func claimVersionNoticeToMaster() -> Bool {
        defer { hasSentVersionNotice = true }
        return !hasSentVersionNotice
    }

    /// Forgets what was already said, so a later game against an incompatible peer is told again.
    /// A game ends here; the controller itself lives for the whole app run.
    /// See CODE_AUDIT_26 §5.18.
    func resetVersionNotices() {
        versionNoticeConnectionIds = []
        hasSentVersionNotice = false
        reportedMismatches = []
    }

    /// Whether `mismatch` is news to the person at this device.
    func claimMismatchReport(_ mismatch: GameVersionMismatch) -> Bool {
        reportedMismatches.insert(mismatch).inserted
    }

    private(set) var masterStore: (any MasterNetworkControllable)?
    private(set) var playerStore: (any PlayerNetworkControllable)?

    init(name: String) {
        self.name = name
    }

    func setControllers(master: any MasterNetworkControllable, player: any PlayerNetworkControllable) {
        masterStore = master
        playerStore = player
    }

    /// Whether an audio item is a playlist, which has its own SharePlay Journal slot (see
    /// `SharePlayJournalSlot`). Set by the game master's controller; nothing is a playlist
    /// without it.
    var isAudioPlaylist: (@MainActor (UUID) -> Bool)?

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
