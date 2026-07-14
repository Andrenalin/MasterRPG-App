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
final class GameNetworkController: Sendable {
    let proxy: Bool
    let model: GameNetworkControllerModel

    @MainActor
    let sharePlayStore: RPGSharePlayController
    @MainActor
    private var delegateTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Static builders

    @MainActor static let defaultMasterStoreBuilder: (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = { name, delegate in
        MasterNetworkController(name: name, delegate: delegate, listnerBuilder: MasterNetworkController.gameListnerBuilder())
    }

    @MainActor static let directPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, delegate: delegate)
    }

    @MainActor static let proxyPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, proxy: true, delegate: delegate)
    }

    // MARK: Inits

    /// Designated init — used by tests to inject spy implementations.
    @MainActor
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
        Logger.networking.debug("GameNetworkController: Init \(name, privacy: .public) proxy=\(proxy)")
    }

    /// Convenience init for direct (non-proxy) mode.
    @MainActor
    convenience init(name: String = "") {
        self.init(
            name: name,
            proxy: false,
            masterBuilder: Self.defaultMasterStoreBuilder,
            playerBuilder: Self.directPlayerStoreBuilder
        )
    }

    /// Convenience init for proxy mode.
    @MainActor
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
        Logger.networking.debug("GameNetworkController: deinit \(name, privacy: .public)")
    }

    /// Sets up SharePlay integration. Only meaningful in direct (non-proxy) mode.
    @MainActor
    func setup(gameModel: GameRootModel) {
        guard !model.isSetup else { return }
        sharePlayStore.setup(gameModel: gameModel)
        sharePlayStore.delegate = self
        model.didSetup()
    }

    @MainActor
    func setupLocal() {
        model.setLocalPlayers(to: true)
    }
}

// MARK: - Control

extension GameNetworkController {
    @MainActor
    func startMasterGame(game: GameConfigModel, titleImage: AKImage?) async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start master game \(name, privacy: .public)")
        model.masterStore?.startStreaming()
        if !proxy && sharePlayStore.canActivateSharePlay {
            // Subscribe to sessions() before activating, so the session delivered
            // by activate() can never race past the for-await loop.
            sharePlayStore.joinGame()
            sharePlayStore.startSharing(with: game.master.adventureTitle, image: titleImage)
        }
    }

    @MainActor
    func startProxyServer() {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start proxy server \(name, privacy: .public)")
        model.masterStore?.startProxyStreaming()
    }

    @MainActor
    func startPlayerGame(to model: BrowserGameModel?) async -> Bool {
        let name = self.model.name
        Logger.networking.debug("GameNetworkController: start player game \(name, privacy: .public)")
        if let model {
            await self.model.playerStore?.toggleConnection(to: model)
            return true
        }
        if !proxy && sharePlayStore.canActivateSharePlay {
            sharePlayStore.joinGame()
            return true
        }
        return false
    }

    @MainActor
    func stopGame() async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: stop game \(name, privacy: .public)")
        delegateTasks.values.forEach { $0.cancel() }
        delegateTasks.removeAll()
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
    }
}

// MARK: - Master send

extension GameNetworkController {
    @MainActor
    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        // The master receives SharePlay messages through the same delegate with
        // the participant id in the connection slot. The store reports whether
        // it could deliver to that id; if not, fall back to the broadcast path —
        // the message's targetId keeps other peers from processing it.
        let delivered = await model.masterStore?.sendResponse(data: data, id: connectionId) ?? false
        guard delivered else {
            await sendPlayer(data: data, fileJournal: data.usesFileJournal)
            return
        }
        if !proxy && model.hasLocalPlayer {
            await model.playerDelegate?.received(data)
        }
    }

    @MainActor
    func sendPlayer(data: GameNetworkModel, fileJournal: Bool = false) async {
        await model.masterStore?.sendResponse(data: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        }
    }
}

// MARK: - MasterNetworkControllerDelegate

extension GameNetworkController: MasterNetworkControllerDelegate {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        if !proxy {
            await model.masterDelegate?.lostPlayer(for: connectionId)
        }
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        if proxy {
            await model.masterProxyDelegate?.readyProxy(for: connectionId)
        } else {
            await model.masterDelegate?.ready(for: connectionId)
        }
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("GameNetworkController: Master Received invalid game data from \(connectionId)")
            return
        }
        if proxy {
            // Don't resend in proxy mode — would cause an endless relay loop
            await model.masterProxyDelegate?.receivedServerProxy(gameData)
        } else {
            // Fan-out received data to all other peers + SharePlay
            await model.masterStore?.sendResponse(data: gameData, except: connectionId)
            let useFileJournal = fileJournal || gameData.usesFileJournal
            await MainActor.run { sharePlayStore.sendData(gameData, fileJournal: useFileJournal) }
            await model.masterDelegate?.received(gameData, connectionId: connectionId)
        }
    }
}

// MARK: - Player send

extension GameNetworkController {
    @MainActor
    func sendMaster(data: GameNetworkModel, fileJournal: Bool = false) async {
        if !proxy { guard !model.hasLocalPlayer else { return } }
        await model.playerStore?.request(with: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
        }
    }
}

// MARK: - PlayerNetworkControllerDelegate

extension GameNetworkController: PlayerNetworkControllerDelegate {
    func playerLostMaster() async {
        if proxy {
            await model.playerProxyDelegate?.lostProxyConnection()
        } else {
            await model.playerDelegate?.lostConnection()
        }
    }

    func playerReady() async {
        if proxy {
            await model.playerProxyDelegate?.readyProxy()
        } else {
            await model.playerDelegate?.ready()
        }
    }

    func playerReceived(data: Data?) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("GameNetworkController: Player received invalid game data")
            return
        }
        if proxy {
            await model.playerProxyDelegate?.receivedProxy(gameData)
        } else {
            await model.playerDelegate?.received(gameData)
        }
    }
}

// MARK: - SharePlayControllerDelegate

extension GameNetworkController: SharePlayControllerDelegate {
    @MainActor
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async {
        // The messenger already yields messages in order. Await routing so that
        // order is not lost by creating one unstructured task per message.
        await routeSharePlayUpdate(model, id: id)
    }

    @MainActor
    func handleFileUpdate(_ model: GameNetworkModel) async {
        // Journal snapshots may briefly contain both an old and replacement
        // attachment. Await routing so their established order is preserved;
        // independent unstructured tasks provide no FIFO guarantee.
        await routeSharePlayFileUpdate(model)
    }

    @MainActor
    func handleFileLoadFailure(_ message: GameNetworkModel) async {
        if message.sender.isMaster {
            await model.playerDelegate?.sharePlayFileLoadFailed(message)
        } else {
            // Player-origin journal uploads retain their existing master-side
            // handling; the explicit player recovery request is for content
            // whose authoritative source is the master.
            await routeSharePlayFileUpdate(message)
        }
    }

    @MainActor
    func sharePlayLostPlayer(id: UUID) {
        scheduleDelegateTask {
            await self.model.masterDelegate?.lostPlayer(for: id)
        }
    }

    @MainActor
    func sharePlayLostConnection() {
        scheduleDelegateTask {
            await self.model.playerDelegate?.lostConnection()
        }
    }

    @MainActor
    func sharePlaySessionConfigured() {
        scheduleDelegateTask {
            guard !self.model.hasLocalPlayer else { return }
            await self.model.playerDelegate?.ready()
        }
    }

    @MainActor
    func routeSharePlayUpdate(_ message: GameNetworkModel, id: UUID) async {
        if message.sender.isMaster {
            await model.playerDelegate?.receivedSharePlay(message, participantId: id)
        } else {
            await model.masterDelegate?.received(message, connectionId: id)
            if !model.hasLocalPlayer {
                await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            }
        }

        if model.hasLocalPlayer {
            await model.masterStore?.sendResponse(data: message)
        }
    }

    @MainActor
    func routeSharePlayFileUpdate(_ message: GameNetworkModel) async {
        if message.sender.isMaster {
            await model.playerDelegate?.receivedSharePlayFile(message)
        } else {
            await model.masterDelegate?.receivedFile(message)
            if !model.hasLocalPlayer {
                await model.playerDelegate?.receivedSharePlayFile(message)
            }
        }

        if model.hasLocalPlayer {
            await model.masterStore?.sendResponse(data: message)
        }
    }
}

// MARK: - Utility

extension GameNetworkController {
    func isStreaming() async -> Bool {
        await model.masterStore?.networkModel.isStreaming ?? false
    }

    @MainActor
    func resetName(name: String) {
        model.masterStore?.networkModel.name = name
        model.playerStore?.networkModel.name = name
    }

    @MainActor
    private func scheduleDelegateTask(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        delegateTasks[id] = Task { @MainActor [weak self] in
            await operation()
            self?.delegateTasks.removeValue(forKey: id)
        }
    }
}
