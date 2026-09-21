// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG
#if os(macOS)
import AppKit
#else
import UIKit
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
        gameModel.hasSendPlayer = false
        gameModel.pendingMapRequests = []
        gameModel.pendingAudioRequests = []
        gameModel.requestedRepairIds = []
        gameModel.requestedPdfRepairIds = []
        gameModel.requestedSpaceRepairIds = []
        gameModel.resetMasterStateSequence()
        gameModel.resetAudioListSequence()
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetPresentationSequence()
        gameModel.resetMapContentSequence()
        gameModel.resetSharePlayMasterParticipant()
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
        gameModel.setGameUpdateType(.map)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    /// Clears the space repair-pending flag and marks the space update.
    /// Spans two @MainActor models (`gameModel` and `root.gameModel`), so it
    /// lives on the controller — one @MainActor call keeps both updates
    /// atomic. See CODE_AUDIT §3.1.
    ///
    /// Used to also force the presentation mode to `.immersive` on visionOS;
    /// removed so revealing a Space item never disturbs the current
    /// SharePlay seating (`.window`'s sideBySide or `.tabletop`'s surround
    /// stays as is) — `GameRootViewer`'s reveal handler opens the space
    /// viewer directly, and `SpaceViewer` places the object above the table
    /// itself when it's open, instead of the mode switch doing it.
    func completeSpaceReveal(itemId: UUID) {
        gameModel.requestedSpaceRepairIds.remove(itemId)
        gameModel.setGameUpdateType(.space)
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
