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
            // Pass on only what the master understood: the player's payload is never relayed or
            // held, and an id the master has no audio for is dropped. See CODE_AUDIT_23 §6.3.
            guard let request = root.audioRoot.audioGameControllable.sanitizedPlayRequest(from: model.data),
                  await root.audioRoot.gameControllable.hasItem(id: request.id, version: 0)
            else {
                Logger.networking.debug("MasterController: Ignored malformed or unknown playAudio request from \(model.sender.id, privacy: .public)")
                return nil
            }
            await requestAudioPlay(request)
        case .audioList:
            guard applyAudioList(model) else { return nil }
            await broadcastAudioList()
            // The list may show that this player lacks an audio a play is waiting for.
            for (_, pending) in gameModel.pendingAudioPlays
            where missingPlayers(for: pending).contains(model.sender.id) {
                await deliverPendingAudio(pending, to: [model.sender.id])
            }
            await startCompletePendingAudioPlays()
        default:
            break
        }
        return nil
    }

    /// Lets the game master's audio loop play the playlist again for everyone: the replay goes out
    /// as a play command like a tap on play, so the players start the playlist from its first
    /// track as well. Only the master registers it (a proxy never plays audio for the game), and
    /// `stop()` removes it so a loop outside a game restarts locally again.
    func installAudioLoopReplay() {
        guard !asProxy else { return }
        // The closure lives on the audio model: it holds the controller weakly and no view.
        root.audioRoot.audioGameControllable.setLoopReplayHandler { [weak self] request in
            Task { await self?.requestAudioPlay(request) }
        }
    }

    func removeAudioLoopReplay() {
        guard !asProxy else { return }
        root.audioRoot.audioGameControllable.setLoopReplayHandler(nil)
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
        let missingPlayers = missingPlayers(for: data)
        if missingPlayers.isEmpty {
            await startCompletePendingAudioPlays()
        } else {
            await deliverPendingAudio(data, to: missingPlayers)
        }
    }

    /// The players that lack something the play command `data` needs on every device: the
    /// playlist's start items and the track it names (see `AudioGameStorable.requiredItemIds`).
    /// Not the other tracks of the playlist: they are sent ahead while the track before plays.
    func missingPlayers(for data: NetworkCodableDataType) -> Set<UUID> {
        let audio = root.audioRoot.audioGameControllable
        return Set(audio.requiredItemIds(for: data).flatMap { audio.missingPlayers(ofItem: $0) })
    }

    /// Starts every pending play whose audio all players have by now.
    ///
    /// Not `private` because `MasterController+Control.swift`'s
    /// `performResetPlayers()` also calls this directly, from a different file.
    func startCompletePendingAudioPlays() async {
        for (id, data) in gameModel.pendingAudioPlays
        where missingPlayers(for: data).isEmpty {
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioPlayRetryAttempts[id] = nil
            await broadcastAudioPlay(data)
        }
    }

    /// Stores the audio on the players that lack it, without showing it. Every item the play needs
    /// is its own package, sent to the players that lack that item: a playlist of many files is
    /// never sent at once. The play starts when the receipts are in
    /// (`startCompletePendingAudioPlays`).
    private func deliverPendingAudio(_ data: NetworkCodableDataType, to players: Set<UUID>) async {
        let audio = root.audioRoot.audioGameControllable
        for itemId in audio.requiredItemIds(for: data) {
            let missing = Set(audio.missingPlayers(ofItem: itemId)).intersection(players)
            guard !missing.isEmpty else { continue }
            guard await deliverAudio(id: itemId, to: missing) else {
                scheduleAudioPlayRetry(id: data.id)
                return
            }
            // A pause or a newer play replaced this one while the package was prepared.
            guard gameModel.pendingAudioPlays[data.id] != nil else { return }
        }
    }

    /// Sends the one audio item `id` (its own file, never its other tracks) to `players`, and its
    /// reference to everyone: see `GameNetworkController.sendPresentation`. Returns `false` when
    /// the package could not be prepared.
    @discardableResult
    private func deliverAudio(id: UUID, to players: Set<UUID>) async -> Bool {
        let reference = await root.audioRoot.gameControllable.share(id: id)
        let package: NetworkCodableDataType
        do {
            package = try await root.audioRoot.gameControllable.createGameData(for: id)
        } catch {
            Logger.networking.error("MasterController: Cannot prepare audio \(id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return false
        }
        let message = outgoingMessage(type: .store, subtype: .show, updated: reference)
        await root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPresentation(message, missingPlayers: players) { package }
        return true
    }

    /// After an audio was shown (its own package went out): a playlist's first track, when it is
    /// another item, goes to the players that lack it as a package of its own.
    func showAudioStartItems(of id: UUID) async {
        let audio = root.audioRoot.audioGameControllable
        for itemId in audio.startItemIds(for: id) where itemId != id {
            let missing = Set(audio.missingPlayers(ofItem: itemId))
            guard !missing.isEmpty else { continue }
            await deliverAudio(id: itemId, to: missing)
        }
    }

    /// Sends the track after `trackId` to the players that lack it, while `trackId` plays, so it
    /// is on their devices before it is needed. The master's own device advances at the end of a
    /// track without a message, as every player's device does.
    func prefetchNextAudio(rootId: UUID, after trackId: UUID) async {
        let audio = root.audioRoot.audioGameControllable
        guard let nextId = audio.nextTrackId(after: trackId, in: rootId) else { return }
        let missing = Set(audio.missingPlayers(ofItem: nextId))
        guard !missing.isEmpty else { return }
        await deliverAudio(id: nextId, to: missing)
    }

    /// Lets the game master's device send the next track ahead whenever a track starts on it.
    /// Only the master registers it, and `stop()` removes it.
    func installAudioPrefetch() {
        guard !asProxy else { return }
        // The closure lives on the audio model: it holds the controller weakly and no view.
        root.audioRoot.audioGameControllable.setTrackStartHandler { [weak self] rootId, trackId in
            Task { await self?.prefetchNextAudio(rootId: rootId, after: trackId) }
        }
    }

    func removeAudioPrefetch() {
        guard !asProxy else { return }
        root.audioRoot.audioGameControllable.setTrackStartHandler(nil)
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
