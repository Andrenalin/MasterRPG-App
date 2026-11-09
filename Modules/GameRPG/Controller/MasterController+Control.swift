// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG

// MARK: - Control

extension MasterController {
    func start() async {
        Logger.networking.debug("MasterController: Start")
        root.logGameController.beginDeliverySession(gameModel.deliverySessionId)
        // A code that could not be read at launch (locked keychain) is resolved, and a code changed
        // moments ago is made durable, before it is put to use. See CODE_AUDIT_Join §5.5.
        root.gameJoinCodeModel.refreshFromStorage()
        await root.gameJoinCodeModel.flushPendingWrites()
        installAudioLoopReplay()
        installAudioPrefetch()
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
        removeAudioLoopReplay()
        removeAudioPrefetch()
        clearPendingAudioPlays()
        gameModel.sentMapContentVersions.removeAll()
        gameModel.resetCharacterOwnership()
        gameModel.resetListSequences()
        gameModel.resetSpaceTransformSequence()
        await root.networkStore.stopGame()
        await root.networkProxyStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        root.gameModel.gameRoster.players = []
        root.gameModel.gameControl.controls = []
        root.gameModel.tablePlayers = []
        root.gameModel.pinControllers = [:]
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
            // The connected players plus the game master's table players; a table player whose
            // Character a connected player plays waits until that player leaves.
            let valueGameControllable = root.characterRoot.valueGameControllable
            let pinPlayers = TablePlayerResolver.pinPlayers(
                roster: gameRoster.players,
                tablePlayers: root.gameModel.tablePlayers,
                name: { valueGameControllable.playerPinName(for: $0) }
            )
            root.mapRoot.mapGameControllable.resetPlayerPins(for: pinPlayers)
            // A companion is moved by the player who brought it until the game master decides
            // otherwise; an emptied list stays empty.
            for (companionId, ownerId) in TablePlayerResolver.companionOwners(roster: gameRoster.players)
            where root.gameModel.pinControllers[companionId] == nil {
                root.gameModel.pinControllers[companionId] = [ownerId]
            }
            // Who else may move each pin: the connected devices the game master chose.
            let connectedIds = Set(gameRoster.players.map(\.id))
            root.mapRoot.mapGameControllable.setPlayerPinControllers(
                root.gameModel.pinControllers.mapValues { Array($0.intersection(connectedIds)) }
            )
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                // A pin added while a map is shown stands in its first room, not at (0, 0).
                root.mapRoot.mapGameControllable.synchronizePlayerPins(for: mapId)
            }
            #if !os(tvOS)
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
            #endif
            // Push the changed player pins to everyone right away — otherwise
            // a joining player's pin only appears on the next unrelated map
            // state update.
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                if root.mapRoot.rootModel.isMapStreaming {
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
                } else {
                    // A paused "Share Map" keeps the map private; resuming sends the content
                    // and the state, including the new player's pin. See CODE_AUDIT_19 §5.7.
                    root.mapRoot.rootModel.mapsWithUnsharedStructure.insert(mapId)
                }
                if root.mapRoot.mapGameControllable.battleRoundModel.isRunning,
                   let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                       for: mapId
                   ) {
                    await send(type: .update, subtype: .battleRound, updated: battleUpdate)
                }
            }
        }
        // A newly joined player reports its database-backed audio list from
        // ready(), which delivers what it lacks. Removals can immediately
        // unblock a pending play.
        if Set(players).isSubset(of: previousAudioPlayers) {
            await startCompletePendingAudioPlays()
        }
    }
}
