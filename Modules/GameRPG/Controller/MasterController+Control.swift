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

// MARK: - Control

extension MasterController {
    func start() async {
        Logger.networking.debug("MasterController: Start")
        gameModel.resetPlayerJournalAdmissions()
        gameModel.resetPeerAvailabilitySources()
        root.logGameController.beginDeliverySession(gameModel.deliverySessionID)
        // A code that could not be read at launch (locked keychain) is resolved, and a code changed
        // moments ago is made durable, before it is put to use. See CODE_AUDIT_Join §5.5.
        root.gameJoinCodeModel.refreshFromStorage()
        root.gameJoinCodeModel.flushPendingWrites()
        await root.networkStore.startMasterGame(
            game: root.gameModel.gameConfig,
            titleImage: root.adventureRoot.titleImage(for: root.gameModel.gameConfig.master.adventureId),
            passcode: root.gameJoinCodeModel.masterCode
        )
    }

    func stop() async {
        Logger.networking.debug("MasterController: Stop")
        await messagePipeline.cancelAll()
        resetPlayersTask?.cancel()
        resetPlayersTask = nil
        for task in audioPlayRetryTasks.values {
            task.cancel()
        }
        audioPlayRetryTasks.removeAll()
        gameModel.lastMapRecoveryServed.removeAll()
        gameModel.audioPlayRetryAttempts.removeAll()
        gameModel.pendingAudioPlays.removeAll()
        gameModel.audioTransferPlayers.removeAll()
        gameModel.sentGameItems.removeAll()
        gameModel.resetCharacterOwnership()
        gameModel.resetAudioListSequence()
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetSpaceTransformSequence()
        gameModel.resetDeliveryMessages()
        gameModel.resetPlayerJournalAdmissions()
        gameModel.resetPeerAvailabilitySources()
        await root.networkStore.stopGame()
        await root.networkProxyStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        root.gameModel.gameRoster.players = []
        root.gameModel.gameControl.controls = []
    }

    /// Serializing entry point — see `resetPlayersTask`'s doc comment. Every
    /// call site awaits this, so each caller still only returns once its own
    /// broadcast sequence (and any it was queued behind) has fully run.
    func resetPlayers() async {
        let previous = resetPlayersTask
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.performResetPlayers()
        }
        resetPlayersTask = task
        await task.value
    }

    private func performResetPlayers() async {
        let (gameConfig, gameRoster, gameControl) = (root.gameModel.gameConfig, root.gameModel.gameRoster, root.gameModel.gameControl)

        let previousAudioPlayers = Set(root.audioRoot.gameControllable.gameModel.currentPlayers)
        var players = gameControl.controls.compactMap { $0.show ? $0.id : nil }.sorted()
        if asProxy {
            players.append(gameConfig.master.id)
            players.sort()
        }
        // See CODE_AUDIT_Game §9.18 — Map and Dice have their own reset logic below.
        for controllable in root.fileBackedGameModules {
            controllable.gameModel.setCurrent(players: players)
        }

        var playerNames = gameRoster.players.filter { $0.type != .observer }.map { $0.name }.sorted()
        if asProxy {
            playerNames.append(gameConfig.master.name)
            playerNames.sort()
        }
        root.diceRoot.diceGameControllable.resetPlayerDice(to: playerNames)
        if !asProxy {
            root.mapRoot.mapGameControllable.resetPlayerPins(for: gameRoster.players.filter { $0.type != .observer })
            #if !os(tvOS)
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
            #endif
            // Push the changed player pins to everyone right away — otherwise
            // a joining player's pin only appears on the next unrelated map
            // state update.
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                // Messenger messages have no history. Replay the latest
                // photo-free structural snapshot when the roster changes so a
                // SharePlay participant joining after the Journal publication
                // receives edits made since that base attachment.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: root.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
                )
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId))
                if root.mapRoot.mapGameControllable.battleRoundModel.isRunning,
                   let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                       for: mapId
                   ) {
                    await send(type: .update, subtype: .battleRound, updated: battleUpdate)
                }
            }
        }
        // A newly joined player reports its database-backed audio list from
        // ready(). Wait for that report before deciding whether to transfer.
        // Removals can immediately unblock a pending play.
        if Set(players).isSubset(of: previousAudioPlayers) {
            await continuePendingAudioPlays()
        }
    }
}
