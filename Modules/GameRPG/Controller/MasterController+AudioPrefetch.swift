// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AudioRPG

// The audio prefetch for the next track, split out of MasterController+AudioMessages.swift. See CODE_AUDIT_29 §9.9.

extension MasterController {
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
}
