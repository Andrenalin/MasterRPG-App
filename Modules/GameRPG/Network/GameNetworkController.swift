// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities


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

    let sharePlayStore: RPGSharePlayController

    /// Allowance for the JSON envelope around a relayed payload (ids, names, counters).
    nonisolated static let relayFrameOverheadAllowance = 64 * ByteUnit.kibibyte

    /// Whether a received frame may be relayed byte-for-byte: its size must be consistent
    /// with the decoded payload (base64 in JSON is 4/3 of the raw bytes) plus the envelope.
    /// See CODE_AUDIT_18 §6.2.
    nonisolated static func relayForwardsReceivedBytes(frameByteCount: Int, payloadByteCount: Int) -> Bool {
        frameByteCount <= payloadByteCount / 3 * 4 + 4 + relayFrameOverheadAllowance
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
        await model.masterStore?.waitForHostingSessionReady()
        model.masterStore?.startStreaming(passcode: passcode)
        if !proxy {
            // Kept for a call that starts after the game. See CODE_AUDIT_Game_Shareplay §5.20.
            sharePlayStore.pendingActivation = .init(name: game.master.adventureTitle, image: titleImage)
        }
        if !proxy && sharePlayStore.canActivateSharePlay {
            // Subscribe to sessions() before activating, so the session delivered
            // by activate() can never race past the for-await loop.
            sharePlayStore.joinGame()
            sharePlayStore.startSharing(with: game.master.adventureTitle, image: titleImage)
        }
    }

    func startProxyServer(passcode: String) async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start proxy server \(name, privacy: .private)")
        await model.masterStore?.waitForHostingSessionReady()
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
            // Not only leaving: Messenger, the send queue, deferred retries and Journal loads of
            // the left session would run on, and a quick restart could receive their traffic.
            // `reset()` also leaves the session. See CODE_AUDIT_Game_Shareplay §5.30.
            if !proxy { sharePlayStore.reset() }
        }
        if !proxy {
            sharePlayStore.stopJoin()
            model.setLocalPlayers(to: false)
        }
        model.playerRoutes.reset()
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
