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

// MARK: - Audio Messages

extension MasterController {
    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let audio = root.audioRoot.audioGameControllable
            let wasMissingPlayers = !audio.missingPlayers(for: model.data.id).isEmpty
            let hasPendingPlay = gameModel.pendingAudioPlays[model.data.id] != nil
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await startCompletePendingAudioPlays()
            // Only the master collects the receipts. The one that completes a share is
            // announced, so a player's share button turns to play as well; a pending play
            // announces it with its play command instead.
            if wasMissingPlayers, !hasPendingPlay, audio.missingPlayers(for: model.data.id).isEmpty {
                await broadcastAudioList()
            }
            return nil
        }
        guard model.subType != .failed else { return nil }

        if model.isAssetRequest {
            // An iCloud file that has not downloaded cannot be exported.
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) else { return nil }
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        }
        guard model.type == .update else { return nil }

        switch model.subType {
        case .generic:
            guard model.sender.role == .player,
                  root.gameModel.gameControl.features.audioSharing
            else { return nil }
            await showPlayerContribution(model, controllable: root.audioRoot.gameControllable)
        case .playAudio:
            guard root.gameModel.gameControl.features.audioSharing else { return nil }
            await requestAudioPlay(model.data)
        case .audioList:
            guard applyAudioList(model) else { return nil }
            await broadcastAudioList()
            // The list may show that this player lacks an audio a play is waiting for.
            for (id, _) in gameModel.pendingAudioPlays
            where root.audioRoot.audioGameControllable.missingPlayers(for: id).contains(model.sender.id) {
                await deliverPendingAudio(id: id, to: [model.sender.id])
            }
            await startCompletePendingAudioPlays()
        default:
            break
        }
        return nil
    }

    /// Sends every player the authoritative report list: who has which audio.
    private func broadcastAudioList() async {
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id)
        await send(type: .update, subtype: .audioList, updated: audioList)
    }

    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyAudioList(from: model.sender.id, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.sender.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordAudioList(counter: model.counter, from: model.sender.id)
        return true
    }

    /// Plays an audio for everyone. A play command starts only once every player reported the
    /// file: the players that lack it get it first, and their acknowledgements start it.
    func requestAudioPlay(_ data: NetworkCodableDataType) async {
        if !root.audioRoot.audioGameControllable.shouldPlay(with: data) {
            gameModel.pendingAudioPlays[data.id] = nil
            await broadcastAudioPlay(data)
            return
        }

        gameModel.pendingAudioPlays[data.id] = data
        let missingPlayers = Set(root.audioRoot.audioGameControllable.missingPlayers(for: data.id))
        if missingPlayers.isEmpty {
            await startCompletePendingAudioPlays()
        } else {
            await deliverPendingAudio(id: data.id, to: missingPlayers)
        }
    }

    /// Starts every pending play whose audio all players have by now.
    ///
    /// Not `private` because `MasterController+Control.swift`'s
    /// `performResetPlayers()` also calls this directly, from a different file.
    func startCompletePendingAudioPlays() async {
        for (id, data) in gameModel.pendingAudioPlays
        where root.audioRoot.audioGameControllable.missingPlayers(for: id).isEmpty {
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioPlayRetryAttempts[id] = nil
            await broadcastAudioPlay(data)
        }
    }

    /// Stores the audio on the players that lack it, without showing it: its reference goes to
    /// everyone, its file to `players` (see `GameNetworkController.sendPresentation`).
    private func deliverPendingAudio(id: UUID, to players: Set<UUID>) async {
        let reference = await root.audioRoot.gameControllable.share(id: id)
        let package: NetworkCodableDataType
        do {
            package = try await root.audioRoot.gameControllable.createGameData(for: id)
        } catch {
            Logger.networking.error("MasterController: Cannot prepare pending audio \(id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            scheduleAudioPlayRetry(id: id)
            return
        }
        guard gameModel.pendingAudioPlays[id] != nil else { return }
        let message = outgoingMessage(type: .store, subtype: .show, updated: reference)
        await root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPresentation(message, missingPlayers: players) { package }
    }

    private static let audioPlayRetryDelay: Duration = .seconds(5)
    /// Caps the bounded retry so a permanently failing export (missing or
    /// corrupt file) stops re-exporting after this many attempts instead of
    /// retrying every `audioPlayRetryDelay` for the rest of the session.
    /// See CODE_AUDIT_17 §3.6.
    private static let maxAudioPlayRetryAttempts = 5

    /// Schedules one bounded retry of a pending play whose export failed, replacing any retry
    /// already scheduled for this item — so a persistently failing export doesn't pile up
    /// concurrent attempts. See CODE_AUDIT_Network §5.13.
    private func scheduleAudioPlayRetry(id: UUID) {
        let attempts = (gameModel.audioPlayRetryAttempts[id] ?? 0) + 1
        gameModel.audioPlayRetryAttempts[id] = attempts
        guard attempts <= Self.maxAudioPlayRetryAttempts else {
            Logger.networking.error("MasterController: Dropping pending audio \(id, privacy: .public) after \(attempts, privacy: .public) failed attempts.")
            audioPlayRetryTasks[id]?.cancel()
            audioPlayRetryTasks[id] = nil
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioPlayRetryAttempts[id] = nil
            return
        }

        audioPlayRetryTasks[id]?.cancel()
        audioPlayRetryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.audioPlayRetryDelay)
            guard !Task.isCancelled, let self else { return }
            self.audioPlayRetryTasks[id] = nil
            guard let data = self.gameModel.pendingAudioPlays[id] else { return }
            await self.requestAudioPlay(data)
        }
    }

    private func broadcastAudioPlay(_ data: NetworkCodableDataType) async {
        await send(type: .update, subtype: .playAudio, updated: data)
        let hasLocalPlayer = root.networkStore.model.hasLocalPlayer
        if !hasLocalPlayer {
            // A failed playlist load/playback start used to be silently
            // swallowed here. See CODE_AUDIT_Game §4.2.
            do {
                try await root.audioRoot.audioGameControllable.play(with: data)
            } catch {
                Logger.networking.error("MasterController: Failed to start audio playback for \(data.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
