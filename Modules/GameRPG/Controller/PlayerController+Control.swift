// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import DiceRPG
import MapRPG
#if os(macOS)
#else
#endif

// MARK: - Control

extension PlayerController {
    func start(to model: BrowserGameModel?, joinCode: String = "") async -> Bool {
        Logger.networking.debug("PlayerController: Start")
        // Observers are a read-only local-network role. Do not let a nil Bonjour
        // target silently turn an observer into a SharePlay participant.
        if root.gameModel.gameType == .observer, model == nil {
            return false
        }
        root.gameJoinCodeModel.refreshFromStorage()
        root.gameJoinCodeModel.flushPendingWrites()
        if root.gameModel.gameType == .player {
            // This device also relays for further players — its own stored
            // Player code, not the code just entered to join the master.
            root.networkProxyStore.startProxyServer(passcode: root.gameJoinCodeModel.playerCode)
        } else if root.gameModel.gameType == .proxy {
            return await root.networkProxyStore.startPlayerGame(to: model, passcode: joinCode)
        }
        return await root.networkStore.startPlayerGame(to: model, passcode: joinCode)
    }

    func stop() async {
        Logger.networking.debug("PlayerController: Stop")
        await messagePipeline.cancelAll()
        gameModel.sendCharacterTask?.cancel()
        gameModel.sendCharacterTask = nil
        gameModel.sendCharacterTaskId = nil
        gameModel.proxyFocusTask?.cancel()
        gameModel.proxyFocusTask = nil
        gameModel.proxyFocusTaskId = nil
        // The proxy's own MasterController owns its message pipeline and
        // session state — never torn down previously. See CODE_AUDIT_Game §3.11.
        await proxyMasterController?.stop()
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        gameModel.hasSentPlayer = false
        gameModel.resetForLostConnection(preservingSharePlayRebind: false)
        root.mapRoot.photoPopover.photo = nil
    }

    /// Combines `GameRootModel.applyMasterBroadcast` with `resetPlayers()` in one
    /// @MainActor call so both happen atomically — see CODE_AUDIT §3.1.
    func applyMasterBroadcastAndResetPlayers(
        masterId: UUID,
        masterName: String,
        supporterTier: SupporterTier,
        state: GameMasterStateModel
    ) {
        root.gameModel.applyMasterBroadcast(
            masterId: masterId,
            masterName: masterName,
            supporterTier: supporterTier,
            state: state
        )
        resetPlayers()
    }

    /// Spans two separate @MainActor models (`gameModel` and `root.gameModel`), so
    /// it lives on the controller rather than either model — one @MainActor call
    /// keeps both updates atomic. See CODE_AUDIT §3.1.
    func setMapUpdateTypeAndSyncPawns() {
        gameModel.showMapForLiveUpdate(of: root.mapRoot.gameControllable.gameModel.currentItemId)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    func resetPlayers() {
        let players = root.gameModel.gameControl.controls.compactMap { $0.show ? $0.id : nil }
        let sortedPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        // See CODE_AUDIT_Game §9.18 — Dice has its own reset logic below.
        for controllable in root.fileBackedGameModules {
            controllable.gameModel.currentPlayers = sortedPlayers
        }
        let playerNames = root.gameModel.gameControl.controls.map { $0.name }.sorted()
        root.diceRoot.diceGameControllable.resetPlayerDice(to: [root.gameModel.gameConfig.master.name] + playerNames)
    }
}
