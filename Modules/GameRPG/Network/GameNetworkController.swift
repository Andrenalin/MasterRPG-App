// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities


// GameRelayAdmission/SharePlayDeferredPeerGroupEvents and
// SharePlayPlayerJournalAdmission (+ their supporting types) now live in
// their own files — see CODE_AUDIT §9.10.

/// Unified network controller for both direct-play and proxy-relay modes.
///
/// - `proxy: false` — direct mode: owns SharePlay, fans out received data to all peers.
/// - `proxy: true`  — proxy mode: no SharePlay, no fan-out (avoids relay loops).
///
/// `GameRoot` holds two instances: `networkStore` (direct) and `networkProxyStore` (proxy).
@MainActor
final class GameNetworkController: Sendable {
    let proxy: Bool
    let model: GameNetworkControllerModel
    let relayAdmission = GameRelayAdmission()
    let sharePlayPlayerJournalAdmission = SharePlayPlayerJournalAdmission()
    let sharePlayDeferredPeerGroupEvents = SharePlayDeferredPeerGroupEvents()

    let sharePlayStore: RPGSharePlayController

    /// Only accepted peer-visible events cross a transport bridge. Reports,
    /// acknowledgements, repair requests, screens, and canonicalization inputs
    /// are master-only and must stop at the game master.
    /// Allowance for the JSON envelope around a relayed payload (ids, names, counters).
    nonisolated static let relayFrameOverheadAllowance = 64 * ByteUnit.kibibyte

    /// Whether a received frame may be relayed byte-for-byte: its size must be consistent
    /// with the decoded payload (base64 in JSON is 4/3 of the raw bytes) plus the envelope.
    /// See CODE_AUDIT_18 §6.2.
    nonisolated static func relayForwardsReceivedBytes(frameByteCount: Int, payloadByteCount: Int) -> Bool {
        frameByteCount <= payloadByteCount / 3 * 4 + 4 + relayFrameOverheadAllowance
    }

    nonisolated static func shouldRelayToLAN(_ model: GameNetworkModel) -> Bool {
        guard !model.isJournalAdmissionOnly else { return false }
        if model.sender.isMaster {
            return model.effectiveAudience == .group
        }
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return false }

        // Player Photo/PDF/Space reveals have one peer-visible protocol shape.
        // In particular, `.assetRequest` remains master-only even if a sender
        // explicitly stamps the envelope with `.group`.
        if model.isPlayerFileReveal {
            return model.isPlayerFilePresentationEvent
        }
        if model.data.type == .dice {
            return model.isPlayerDiceGroupEvent
        }
        return true
    }

    // MARK: Static builders

    static let defaultMasterStoreBuilder: (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = { name, delegate in
        MasterNetworkController(name: name, delegate: delegate, listenerBuilder: MasterNetworkController.gameListenerBuilder())
    }

    static let directPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, delegate: delegate)
    }

    static let proxyPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, proxy: true, delegate: delegate)
    }

    // MARK: Inits

    /// Designated init — used by tests to inject spy implementations.
    init(
        name: String,
        proxy: Bool,
        masterBuilder: @escaping (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable,
        playerBuilder: @escaping (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable
    ) {
        self.proxy = proxy
        self.sharePlayStore = RPGSharePlay.store
        self.model = GameNetworkControllerModel(name: name)
        let masterStore = masterBuilder(name, self)
        let playerStore = playerBuilder(name, self)
        model.setControllers(master: masterStore, player: playerStore)
        Logger.networking.debug("GameNetworkController: Init \(name, privacy: .private) proxy=\(proxy)")
    }

    /// Convenience init for direct (non-proxy) mode.
    convenience init(name: String = "") {
        self.init(
            name: name,
            proxy: false,
            masterBuilder: Self.defaultMasterStoreBuilder,
            playerBuilder: Self.directPlayerStoreBuilder
        )
    }

    /// Convenience init for proxy mode.
    convenience init(proxyName name: String = "") {
        self.init(
            name: name,
            proxy: true,
            masterBuilder: Self.defaultMasterStoreBuilder,
            playerBuilder: Self.proxyPlayerStoreBuilder
        )
    }

    deinit {
        let name = model.name
        Logger.networking.debug("GameNetworkController: deinit \(name, privacy: .private)")
    }

    /// Sets up SharePlay integration. Only meaningful in direct (non-proxy) mode.
    func setup(gameModel: GameRootModel) {
        guard !model.isSetup else { return }
        sharePlayStore.setup(gameModel: gameModel)
        sharePlayStore.delegate = self
        model.didSetup()
    }

    func setupLocal() {
        model.setLocalPlayers(to: true)
    }
}

// MARK: - Control

extension GameNetworkController {
    func startMasterGame(game: GameConfigModel, titleImage: AKImage?, passcode: String) async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start master game \(name, privacy: .private)")
        model.masterStore?.startStreaming(passcode: passcode)
        if !proxy && sharePlayStore.canActivateSharePlay {
            // Subscribe to sessions() before activating, so the session delivered
            // by activate() can never race past the for-await loop.
            sharePlayStore.joinGame()
            sharePlayStore.startSharing(with: game.master.adventureTitle, image: titleImage)
        }
    }

    func startProxyServer(passcode: String) {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start proxy server \(name, privacy: .private)")
        model.masterStore?.startProxyStreaming(passcode: passcode)
    }

    func startPlayerGame(to model: BrowserGameModel?, passcode: String) async -> Bool {
        let name = self.model.name
        Logger.networking.debug("GameNetworkController: start player game \(name, privacy: .private)")
        if let model {
            // Waits for the actual handshake outcome — a caller receiving
            // `true` here relies on it to mean "connected", since it goes on
            // to flip the game state to `.started` and navigate into the
            // game screen. See `toggleConnection(to:passcode:)`.
            return await self.model.playerStore?.toggleConnection(to: model, passcode: passcode) ?? false
        }
        if !proxy && sharePlayStore.canActivateSharePlay {
            sharePlayStore.joinGame()
            return true
        }
        return false
    }

    func stopGame() async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: stop game \(name, privacy: .private)")
        if await isStreaming() {
            model.masterStore?.stopStreaming()
            await model.playerStore?.stop()
            if !proxy { sharePlayStore.reset() }
        } else {
            await model.playerStore?.stop()
            if !proxy { sharePlayStore.groupSession?.leave() }
        }
        if !proxy {
            sharePlayStore.stopJoin()
            model.setLocalPlayers(to: false)
        }
        await relayAdmission.reset()
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
    }
}

// MARK: - Master send

extension GameNetworkController {
    /// Delivers a relayed player presentation to the co-located player
    /// controller on the game-master device. The originating message has
    /// already been fanned out to LAN and SharePlay peers, so this path must not
    /// publish it to either transport again.
    func sendLocalPlayer(_ data: GameNetworkModel) async {
        guard !proxy, model.hasLocalPlayer else { return }
        await model.playerDelegate?.received(data)
    }

    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        let delivered = await model.masterStore?.sendResponse(data: data, id: connectionId) ?? false
        guard delivered else {
            Logger.networking.debug("GameNetworkController: Target connection \(connectionId, privacy: .public) is no longer available")
            return
        }
    }

    /// Sends a response back over the transport that carried the request. A
    /// SharePlay participant UUID is not a LAN connection UUID and must never
    /// fall through to a cross-transport broadcast.
    func sendPlayer(_ data: GameNetworkModel, to origin: GameMessageOrigin) async {
        switch origin {
        case let .direct(connectionId):
            if let connectionId {
                await sendPlayer(data, to: connectionId)
            } else {
                await sendPlayer(data: data, fileJournal: data.usesFileJournal)
            }
        case let .sharePlay(participantId):
            sharePlayStore.sendData(
                data,
                fileJournal: data.usesFileJournal,
                participantId: participantId
            )
        case .file:
            // Journal callbacks do not expose the originating participant. The
            // targetId still prevents unrelated peers from applying the repair.
            sharePlayStore.sendData(data, fileJournal: data.usesFileJournal)
        case .local:
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        case let .proxy(connectionId):
            if let connectionId {
                await sendPlayer(data, to: connectionId)
            }
        }
    }

    func sendPlayer(data: GameNetworkModel, fileJournal: Bool = false) async {
        await model.masterStore?.sendResponse(data: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        }
    }

    /// Relays a host-remapped proxy presentation to every private mirror except
    /// the one that originated it. The originating mirror has already applied
    /// its own action and sending it back there would manufacture a second
    /// receipt for the same user gesture.
    func sendPlayer(data: GameNetworkModel, except connectionId: ConnectionController.ID) async {
        guard proxy else { return }
        await model.masterStore?.sendResponse(data: data, except: connectionId)
    }
}

// MARK: - Player send

extension GameNetworkController {
    func sendMaster(data: GameNetworkModel, fileJournal: Bool = false) async {
        if !proxy { guard !model.hasLocalPlayer else { return } }
        await model.playerStore?.request(with: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
        }
    }
}

// MARK: - Utility

extension GameNetworkController {
    func isStreaming() async -> Bool {
        model.masterStore?.networkModel.isStreaming ?? false
    }

    func resumeAfterActivation() {
        model.masterStore?.resumeAfterActivation()
    }

    func resetName(name: String, supporterTier: SupporterTier = .none) {
        model.masterStore?.networkModel.name = name
        model.masterStore?.networkModel.supporterTier = supporterTier
        model.playerStore?.networkModel.name = name
        model.playerStore?.networkModel.supporterTier = supporterTier
    }

}
