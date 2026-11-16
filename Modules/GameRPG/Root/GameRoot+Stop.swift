// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import os.log
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

// MARK: - Stop Game

extension GameRoot {
    func stopGame() async {
        stopGeneration += 1
        // Link actions (share/show from a text link) still running belong to the game that ends.
        LinkActionTasks.cancelAll()
        // Coalesce concurrent callers onto the single in-flight teardown instead of running
        // it twice (or racing a fresh `startGame` — see `awaitInFlightStop()`).
        if let stopGameTask {
            await stopGameTask.value
            return
        }
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performStopGame()
            // Cleared by the teardown itself, without a suspension after it ended: a caller that
            // resumed late used to clear the task of a later stop, or leave a finished one that a
            // later `stopGame` coalesced onto without tearing anything down.
            if stopGameTaskToken == token {
                stopGameTask = nil
                stopGameTaskToken = nil
            }
        }
        stopGameTask = task
        stopGameTaskToken = token
        await task.value
    }

    func awaitInFlightStop() async {
        await stopGameTask?.value
    }

    /// A media-services reset replaces the audio engine and its playback coordinator: the
    /// SharePlay controller must coordinate the new one, or the players hear nothing for the rest
    /// of the session. See CODE_AUDIT_Audio2 §5.9.
    func installAudioCoordinatorChangeHandler() {
        audioRoot.setAudioCoordinatorChangeHandler { [weak self] coordinator in
            self?.networkStore.sharePlayStore.setup(audioCoordinator: coordinator)
        }
    }

    func performStopGame() async {
        cancelOwnedTasks()
        audioRoot.setAudioCoordinatorChangeHandler(nil)
        mapRoot.mapGameControllable.resetBattleRound()
        battleRoundBroadcastLog.reset()
        await statisticsModel.checkpoint(participants: currentStatisticParticipants())
        await statisticsModel.finishSession()
        gameModel.playerGameStarted = false
        gameModel.gameConfig.state = .stopped
        // Guests of the 3D table belong to the game that ends here. See CODE_AUDIT_21 §5.12.
        gameModel.tableGuests = [:]
        gameModel.tableGuestMasterId = nil
        await gameModel.masterController?.stop()
        gameModel.masterController = nil
        await gameModel.playerController?.stop()
        gameModel.playerController?.uninstallMapPhotoActions()
        gameModel.playerController = nil
        // Only now: a message built while the controllers were stopping (a pending receipt, a
        // debounced value update) must not go out under the empty config's random master id.
        // See CODE_AUDIT_Game_Shareplay §5.25.
        gameModel.gameConfig = .empty
        await adventureRoot.adventureGameControllable.resetGame()
        // Bytes peers sent for files not downloaded here are only for the running game.
        FileUrlDataController.releaseHeldPeerData()
        // Other apps' audio may resume once the game's audio is not playing.
        audioRoot.releaseAudioSession()
        #if !os(tvOS)
        gameModel.gameTableModel = nil
        #endif
        #if os(visionOS)
        gameModel.shareState = GameShareStateModel()
        #endif

        KeepAwakeModel.shared.release(.game)
    }
}
