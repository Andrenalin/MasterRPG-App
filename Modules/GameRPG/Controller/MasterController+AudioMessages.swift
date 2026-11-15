// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AudioRPG

// MARK: - Audio Messages

extension MasterController {
    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let audio = root.audioRoot.audioGameControllable
            // A receipt counts for the version the master holds now: one for a file the master
            // replaced since is stale, and that player still lacks the current one.
            // See CODE_AUDIT_Audio2 §5.13.
            let baseline = await root.audioRoot.gameControllable.networkVersion(for: model.data.id)
            audio.setMasterVersion(itemId: model.data.id, version: baseline)
            guard model.data.effectiveAssetVersion == baseline else { return nil }
            let wasMissingPlayers = !audio.missingPlayers(for: model.data.id).isEmpty
            let hasPendingPlay = gameModel.pendingAudioPlays[model.data.id] != nil
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await startCompletePendingAudioPlays()
            await joinRunningAudioPlay(playerId: model.sender.id)
            resumeHeldAudioPrefetch()
            // Only the master collects the receipts. The one that completes a share is
            // announced, so a player's share button turns to play as well; a pending play
            // announces it with its play command instead.
            if wasMissingPlayers, !hasPendingPlay, audio.missingPlayers(for: model.data.id).isEmpty {
                await broadcastAudioList()
            }
            return nil
        }
        if model.subType == .failed {
            await handleAudioDeliveryFailure(model)
            return nil
        }

        if model.isAssetRequest {
            // Answered from the package `deliverAudio` just exported (or joins the export that
            // still runs) instead of reading the whole track again inside the serial master
            // pipeline, where the other players' receipts wait behind it. The request itself is
            // answered like the one of a file-backed module. See CODE_AUDIT_Game_Photo_Audio
            // §3.2 and §9.1.
            return try await answerAssetRequest(
                for: model,
                hasLocalFileData: { await root.audioRoot.audioGameControllable.awaitLocalFileData(for: model.data.id) },
                package: { try await audioPackage(for: model.data.id) }
            )
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
            // The list may show that this player lacks an audio a play is waiting for. A pause
            // or a newer play can replace the entry at any of these awaits, so it is read
            // again before each delivery. See CODE_AUDIT_Audio2 §3.1.
            for pendingId in Array(gameModel.pendingAudioPlays.keys) {
                guard let pending = gameModel.pendingAudioPlays[pendingId],
                      missingPlayers(for: pending).contains(model.sender.id)
                else { continue }
                await deliverPendingAudio(pending, to: [model.sender.id])
            }
            await startCompletePendingAudioPlays()
            await joinRunningAudioPlay(playerId: model.sender.id)
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
        // The replay goes through the ordered network actions, so a pause the game master
        // tapped just before cannot be overtaken by it, and it ends with the game.
        // See CODE_AUDIT_Audio2 §3.2.
        root.audioRoot.audioGameControllable.setLoopReplayHandler { [weak self] request in
            guard let self else { return }
            self.root.scheduleNetworkAction { [weak self] in
                await self?.requestAudioPlay(request)
            }
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
              gameModel.canApplyList(.audio, from: model.sender.id, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.sender.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordList(.audio, counter: model.counter, from: model.sender.id)
        return true
    }

    /// Plays an audio for everyone. A play command starts only once every player reported the
    /// file: the players that lack it get it first, and their acknowledgements start it.
    ///
    /// BY DESIGN (CODE_AUDIT_Game_Photo_Audio §7.6): the music starts together, so the play waits
    /// for the slowest player up to `audioPlayDeadline`; it does not start at the first receipt.
    /// Audio therefore feels slower than a photo, which shows on each device on arrival. Do not
    /// report the gate again; shorten what is in front of it instead.
    ///
    /// The game has a single audio stream: any new play or pause replaces the play that still
    /// waits for a player's file, so it cannot start later and replace what the game master
    /// chose since. See CODE_AUDIT_Audio2 §5.1.
    func requestAudioPlay(_ data: NetworkCodableDataType) async {
        clearPendingAudioPlays()
        if !root.audioRoot.audioGameControllable.shouldPlay(with: data) {
            await broadcastAudioPlay(data, plays: false)
            return
        }
        await startPendingAudioPlay(data)
    }

    /// Starts the play for the players that are ready once the deadline passed: a player that
    /// never answers (a ghost, a lost receipt, a stalled download) must not hold the music of the
    /// whole table. The players it started without join the running play when their file
    /// arrives (`joinRunningAudioPlay`). See CODE_AUDIT_Game_Shareplay §5.7.
    private func scheduleAudioPlayDeadline(for id: UUID) {
        guard audioPlayDeadlineTasks[id] == nil else { return }
        let deadline = audioPlayDeadline
        audioPlayDeadlineTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled, let self else { return }
            await self.audioPlayDeadlineExpired(id: id)
        }
    }

    func audioPlayDeadlineExpired(id: UUID) async {
        audioPlayDeadlineTasks[id] = nil
        guard let data = gameModel.pendingAudioPlays[id] else { return }
        let audio = root.audioRoot.audioGameControllable
        let missing = missingPlayers(for: data)
        guard !missing.isEmpty else { return }
        Logger.networking.error("MasterController: Audio \(id, privacy: .public) starts after its deadline without \(missing.count, privacy: .public) player(s).")
        for itemId in audio.requiredItemIds(for: data) {
            for playerId in audio.missingPlayers(ofItem: itemId) where missing.contains(playerId) {
                gameModel.abandonAudioDelivery(itemId: itemId, playerId: playerId)
            }
        }
        lateAudioPlayers.formUnion(missing)
        await startCompletePendingAudioPlays()
    }

    /// Sends the running play to `playerId` alone when it started without them and they have the
    /// files now.
    func joinRunningAudioPlay(playerId: UUID) async {
        guard lateAudioPlayers.contains(playerId), let running = runningAudioPlay else { return }
        let audio = root.audioRoot.audioGameControllable
        guard audio.requiredItemIds(for: running).allSatisfy({ !audio.missingPlayers(ofItem: $0).contains(playerId) })
        else { return }
        lateAudioPlayers.remove(playerId)
        await send(type: .update, subtype: .playAudio, updated: running, playerId: playerId)
    }

    /// Notes the master's current version of every item the play needs: a file the game master
    /// replaced since a player reported it is missing again for that player.
    private func recordAudioMasterVersions(for data: NetworkCodableDataType) async {
        let audio = root.audioRoot.audioGameControllable
        for itemId in audio.requiredItemIds(for: data) {
            audio.setMasterVersion(itemId: itemId, version: await root.audioRoot.gameControllable.networkVersion(for: itemId))
        }
    }

    /// Records `data` as the play that waits for the players' files and starts it or delivers
    /// what is missing.
    private func startPendingAudioPlay(_ data: NetworkCodableDataType) async {
        await recordAudioMasterVersions(for: data)
        gameModel.pendingAudioPlays[data.id] = data
        let missingPlayers = missingPlayers(for: data)
        if missingPlayers.isEmpty {
            await startCompletePendingAudioPlays()
        } else {
            // A retry is the same play again and keeps its deadline.
            scheduleAudioPlayDeadline(for: data.id)
            startAudioDelivery(data, to: missingPlayers)
        }
    }

    /// Delivers what the pending play lacks in a task of its own, not inside the game master's
    /// action chain: exporting and handing off a large file would hold every later action (a
    /// map shown, dice, a pause) until it is done. The task is replaced by the next play and
    /// ends with a pause and with the game. See CODE_AUDIT_Audio2 §7.4.
    private func startAudioDelivery(_ data: NetworkCodableDataType, to players: Set<UUID>) {
        audioDeliveryTask?.cancel()
        audioDeliveryTask = Task { [weak self] in
            await self?.deliverPendingAudio(data, to: players)
        }
    }

#if DEBUG
    /// A test affordance: returns once the delivery for the pending play is done.
    func waitForAudioDeliveries() async {
        await audioDeliveryTask?.value
    }

    /// A test affordance: returns once the look-ahead that sends the next track is done.
    func waitForAudioPrefetch() async {
        await audioPrefetchTask?.value
    }
#endif

    /// Forgets the pending play `id` with its retry task, attempts and failure counts.
    func clearPendingAudioPlay(_ id: UUID) {
        audioPlayDeadlineTasks[id]?.cancel()
        audioPlayDeadlineTasks[id] = nil
        audioPlayRetryTasks[id]?.cancel()
        audioPlayRetryTasks[id] = nil
        gameModel.audioPlayRetryAttempts[id] = nil
        gameModel.pendingAudioPlays[id] = nil
    }

    /// Forgets every pending play: a new play, a pause and the end of the game.
    func clearPendingAudioPlays() {
        audioDeliveryTask?.cancel()
        audioDeliveryTask = nil
        // A new play or a pause replaces the music a late player could still join.
        lateAudioPlayers.removeAll()
        for task in audioPlayRetryTasks.values {
            task.cancel()
        }
        audioPlayRetryTasks.removeAll()
        for task in audioPlayDeadlineTasks.values {
            task.cancel()
        }
        audioPlayDeadlineTasks.removeAll()
        gameModel.audioPlayRetryAttempts.removeAll()
        gameModel.pendingAudioPlays.removeAll()
        gameModel.resetAudioDeliveryFailures()
    }

    /// The players that lack something the play command `data` needs on every device: the
    /// playlist's start items and the track it names (see `AudioGameStorable.requiredItemIds`).
    /// Not the other tracks of the playlist: they are sent ahead while the track before plays.
    func missingPlayers(for data: NetworkCodableDataType) -> Set<UUID> {
        let audio = root.audioRoot.audioGameControllable
        // A player whose import of an item kept failing is given up on: the play starts
        // without them, and the share list still shows them as lacking the file.
        return Set(audio.requiredItemIds(for: data).flatMap { itemId in
            audio.missingPlayers(ofItem: itemId).filter {
                !gameModel.isAudioDeliveryAbandoned(itemId: itemId, playerId: $0)
            }
        })
    }

    /// A player received an audio package but could not use it, or lost it while it loaded. The
    /// first failure sends the package to that player once more; the second one makes the play
    /// go on without that player. A play that already started without the player
    /// (`lateAudioPlayers`) takes the retry as well, so the player can still join it.
    /// See CODE_AUDIT_Game_Photo_Audio §5.2.
    private func handleAudioDeliveryFailure(_ model: GameNetworkModel) async {
        guard model.sender.role == .player else { return }
        let itemId = model.data.id
        let playerId = model.sender.id
        let audio = root.audioRoot.audioGameControllable
        let isPending = gameModel.pendingAudioPlays.values.contains { audio.requiredItemIds(for: $0).contains(itemId) }
        let joinsRunningPlay = lateAudioPlayers.contains(playerId)
            && runningAudioPlay.map { audio.requiredItemIds(for: $0).contains(itemId) } == true
        guard isPending || joinsRunningPlay else { return }
        guard audio.missingPlayers(ofItem: itemId).contains(playerId) else { return }

        if gameModel.claimAudioDeliveryRetry(itemId: itemId, playerId: playerId) {
            Logger.networking.error("MasterController: Audio \(itemId, privacy: .public) failed for player \(playerId, privacy: .public); sending it once more.")
            await deliverAudio(id: itemId, to: [playerId])
            return
        }
        guard isPending else { return }
        gameModel.abandonAudioDelivery(itemId: itemId, playerId: playerId)
        Logger.networking.error("MasterController: Giving up audio \(itemId, privacy: .public) for player \(playerId, privacy: .public) after it failed to import it twice.")
        resumeHeldAudioPrefetch()
        await startCompletePendingAudioPlays()
    }

    /// Starts every pending play whose audio all players have by now.
    ///
    /// Not `private` because `MasterController+Control.swift`'s
    /// `performResetPlayers()` also calls this directly, from a different file.
    func startCompletePendingAudioPlays() async {
        // The entry is read again for every id: a pause or a newer play processed during the
        // broadcast's await removes it. See CODE_AUDIT_Audio2 §3.1.
        for id in Array(gameModel.pendingAudioPlays.keys) {
            guard let data = gameModel.pendingAudioPlays[id], missingPlayers(for: data).isEmpty else { continue }
            clearPendingAudioPlay(id)
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
            guard !Task.isCancelled else { return }
            let missing = Set(audio.missingPlayers(ofItem: itemId)).intersection(players)
            guard !missing.isEmpty else { continue }
            // A pause or a newer play replaces this play while a large track is exported: that
            // track is not uploaded then, it would only delay the package of the new play in the
            // shared audio slot. See CODE_AUDIT_Game_Photo_Audio §5.4.
            let isSuperseded = { [self] in Task.isCancelled || gameModel.pendingAudioPlays[data.id] == nil }
            guard await deliverAudio(id: itemId, to: missing, isSuperseded: isSuperseded) else {
                // A pause, a newer play or the end of the game may have replaced this play
                // while the package was prepared: nothing is left to retry then.
                if !Task.isCancelled, gameModel.pendingAudioPlays[data.id] != nil {
                    scheduleAudioPlayRetry(id: data.id)
                }
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
    private func deliverAudio(
        id: UUID,
        to players: Set<UUID>,
        isSuperseded: () -> Bool = { false }
    ) async -> Bool {
        // An evicted iCloud file is downloaded first, even if that means waiting: the delivery
        // only goes out from a file that can be read. It fails (and the bounded retry tries
        // again) only when iCloud never delivers or the delivery is cancelled.
        guard await root.audioRoot.audioGameControllable.awaitLocalFileData(for: id) else {
            Logger.networking.error("MasterController: Audio \(id, privacy: .public) is not downloaded yet.")
            return false
        }
        let reference = await root.audioRoot.gameControllable.share(id: id)
        let package: NetworkCodableDataType
        do {
            package = try await audioPackage(for: id)
        } catch {
            Logger.networking.error("MasterController: Cannot prepare audio \(id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return false
        }
        let message = outgoingMessage(type: .store, subtype: .show, updated: reference)
        root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPresentation(message, missingPlayers: players, isSuperseded: isSuperseded) { package }
        return true
    }

    /// The package of the audio `id`. A delivery that starts while an identical export still runs
    /// waits for that export instead of reading the whole file into memory again (a join, a
    /// retry and a prefetch can ask for the same track at once). See CODE_AUDIT_Audio2 §7.3.
    /// The newest export is also kept in the package cache for as long as the file is unchanged,
    /// so the asset requests of the players that follow the push cost no export.
    /// See CODE_AUDIT_Game_Photo_Audio §3.2.
    func audioPackage(for id: UUID) async throws -> NetworkCodableDataType {
        let audio = root.audioRoot.gameControllable
        return try await audioPackages.value(for: id) { [self] in
            try await cachedPackage(module: .audio, itemId: id, controllable: audio)
        }
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
    ///
    /// The Journal keeps one attachment per slot, and the next track takes the slot of the
    /// current one: a player still downloading the current track would lose it. The look-ahead
    /// therefore waits until no player is loading the track that plays (their receipt, a failure
    /// report or `audioPrefetchHold` ends the wait). `force` skips the wait.
    /// See CODE_AUDIT_Game_Photo_Audio §5.1.
    func prefetchNextAudio(rootId: UUID, after trackId: UUID, force: Bool = false) async {
        let audio = root.audioRoot.audioGameControllable
        guard let nextId = audio.nextTrackId(after: trackId, in: rootId) else { return }
        let missing = Set(audio.missingPlayers(ofItem: nextId))
        guard !missing.isEmpty else { return }
        if !force, !playersLoading(itemId: trackId).isEmpty {
            holdAudioPrefetch(rootId: rootId, trackId: trackId)
            return
        }
        // A newer track starting cancels this task, and the package is not sent for a track
        // that no longer plays.
        await deliverAudio(id: nextId, to: missing, isSuperseded: { Task.isCancelled })
    }

    /// How long the look-ahead waits for a player that is still loading the current track, so a
    /// player that never answers cannot stop the next track from reaching the others.
    static let audioPrefetchHold: Duration = .seconds(60)

    /// The players that may still be downloading `itemId`: those without a receipt, except the
    /// ones the master gave up on after a failure. A player the play started without at its
    /// deadline is still downloading.
    private func playersLoading(itemId: UUID) -> Set<UUID> {
        Set(root.audioRoot.audioGameControllable.missingPlayers(ofItem: itemId).filter {
            !gameModel.isAudioDeliveryAbandoned(itemId: itemId, playerId: $0) || lateAudioPlayers.contains($0)
        })
    }

    private func holdAudioPrefetch(rootId: UUID, trackId: UUID) {
        heldAudioPrefetch = (rootId, trackId)
        audioPrefetchHoldTask?.cancel()
        audioPrefetchHoldTask = Task { [weak self] in
            try? await Task.sleep(for: Self.audioPrefetchHold)
            guard !Task.isCancelled, let self,
                  let held = self.heldAudioPrefetch, held.trackId == trackId
            else { return }
            Logger.networking.error("MasterController: Sending the track after \(trackId, privacy: .public) although a player still loads it.")
            self.heldAudioPrefetch = nil
            self.startAudioPrefetch(rootId: rootId, trackId: trackId, force: true)
        }
    }

    /// Lets the held look-ahead go on once nobody is loading the track that plays.
    func resumeHeldAudioPrefetch() {
        guard let held = heldAudioPrefetch, playersLoading(itemId: held.trackId).isEmpty else { return }
        heldAudioPrefetch = nil
        audioPrefetchHoldTask?.cancel()
        audioPrefetchHoldTask = nil
        startAudioPrefetch(rootId: held.rootId, trackId: held.trackId)
    }

    /// Only a package goes out, so it does not need the order of the game master's actions, and
    /// it must not hold them: a task of its own, replaced by the next track and cancelled by
    /// `stop()`. See CODE_AUDIT_Audio2 §7.4.
    private func startAudioPrefetch(rootId: UUID, trackId: UUID, force: Bool = false) {
        audioPrefetchTask?.cancel()
        audioPrefetchTask = Task { [weak self] in
            await self?.prefetchNextAudio(rootId: rootId, after: trackId, force: force)
        }
    }

    /// Lets the game master's device send the next track ahead whenever a track starts on it.
    /// Only the master registers it, and `stop()` removes it.
    func installAudioPrefetch() {
        guard !asProxy else { return }
        // The closure lives on the audio model: it holds the controller weakly and no view.
        root.audioRoot.audioGameControllable.setTrackStartHandler { [weak self] rootId, trackId in
            guard let self else { return }
            // A new track replaces the look-ahead that still waits for the one before.
            self.heldAudioPrefetch = nil
            self.audioPrefetchHoldTask?.cancel()
            self.audioPrefetchHoldTask = nil
            self.startAudioPrefetch(rootId: rootId, trackId: trackId)
        }
    }

    func removeAudioPrefetch() {
        guard !asProxy else { return }
        audioPrefetchTask?.cancel()
        audioPrefetchTask = nil
        audioPrefetchHoldTask?.cancel()
        audioPrefetchHoldTask = nil
        heldAudioPrefetch = nil
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
            clearPendingAudioPlay(id)
            return
        }

        audioPlayRetryTasks[id]?.cancel()
        audioPlayRetryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.audioPlayRetryDelay)
            guard !Task.isCancelled, let self else { return }
            self.audioPlayRetryTasks[id] = nil
            guard let data = self.gameModel.pendingAudioPlays[id] else { return }
            // Not `requestAudioPlay`: a retry is the same play again and must keep its attempts.
            await self.startPendingAudioPlay(data)
        }
    }

    private func broadcastAudioPlay(_ data: NetworkCodableDataType, plays: Bool = true) async {
        // A pause ends the music a late player could still join.
        runningAudioPlay = plays ? data : nil
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
