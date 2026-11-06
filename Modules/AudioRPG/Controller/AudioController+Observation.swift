// @copyright André Trettin

import AVFoundation
import Combine
import CoreRPG
import Observation
import OSLog

// MARK: - Playback observation

/// Follows the player (status, track end, time) and the shared audio of a SharePlay session,
/// and logs what the player reports.
extension AudioController {
    @MainActor func observePlayback() {
        guard model.subscriptions.isEmpty else { return }

        // One ordered consumer per source instead of a `Task` per event, which could apply
        // `timeControlStatus` changes out of order. The tasks are wrapped in
        // `AnyCancellable`s so the existing subscription teardown cancels them.
        // See CODE_AUDIT_18 §4.2.
        let player = model.player
        // KVO publishers don't buffer and `.values` only has demand while the loop waits, so
        // a change landing mid-iteration was dropped. The buffer keeps demand open, and each
        // element is only a wake-up: the live status is read so a stale buffered value
        // never wins. See CODE_AUDIT_19 §3.3.
        let statusChanges = player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest)
        let statusTask = Task { @MainActor [weak self] in
            for await _ in statusChanges.values {
                guard let self else { return }
                self.model.isPlaying = player.timeControlStatus == .playing
                Self.logPlaybackStatus(of: player)
            }
        }
        // A track that cannot be played never changes `timeControlStatus`; only its item says why.
        let itemStatusChanges = player.publisher(for: \.currentItem?.status)
            .removeDuplicates()
            .buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest)
        let itemStatusTask = Task { @MainActor in
            for await status in itemStatusChanges.values where status == .failed {
                let error = player.currentItem?.error
                Logger.audioController.error("🎧 Track failed to load: \(error?.logIdentifier ?? "unknown", privacy: .public) \(error?.localizedDescription ?? "", privacy: .private)")
            }
        }
        let endOfItemTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                // The notification fires for every AVPlayerItem in the process — match it
                // against our current item before advancing the playlist.
                guard let self,
                      let endedItem = notification.object as? AVPlayerItem,
                      let current = self.model.player.currentItem,
                      current === endedItem else { continue }
                self.resetPlaylist(complete: true)
            }
        }
        model.add(subscriptions: [
            AnyCancellable { statusTask.cancel() },
            AnyCancellable { itemStatusTask.cancel() },
            AnyCancellable { endOfItemTask.cancel() }
        ])

        addTimeObserver()
    }

    /// Why the player is not playing, if it waits: a SharePlay participant waits for the others
    /// (`waitingForCoordinatedPlayback`) or for its own buffering.
    @MainActor private static func logPlaybackStatus(of player: AVPlayer) {
        switch player.timeControlStatus {
        case .playing:
            Logger.audioController.debug("🎧 Playing at rate \(player.rate, privacy: .public)")
        case .paused:
            Logger.audioController.debug("🎧 Paused")
        case .waitingToPlayAtSpecifiedRate:
            let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
            Logger.audioController.debug("🎧 Waiting to play: \(reason, privacy: .public)")
        @unknown default:
            break
        }
    }

    @MainActor private func addTimeObserver() {
        removeTimeObserver()
        let timeInterval = CMTime(value: 1, timescale: 1)
        // Delivered on the main queue, so the update runs in order without allocating a
        // `Task` per tick. See CODE_AUDIT_18 §4.2.
        model.timeObserver = model.player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
            assumeMainActorIsolated {
                self?.updateCurrentTime(time: time)
            }
        }
    }

    @MainActor private func updateCurrentTime(time: CMTime) {
        guard let duration = model.player.currentItem?.duration else { return }
        // An item whose duration is not known yet (or a stream) reports NaN or infinity; neither
        // may reach the progress bar or the now-playing info. See CODE_AUDIT_23 §5.22.
        let elapsed = time.seconds.isFinite ? time.seconds : 0
        let total = duration.seconds.isFinite ? duration.seconds : elapsed
        model.playerTime = PlayerTime(elapsedTime: elapsed, remainingTime: total - elapsed)

        // Track advancing is driven by AVPlayerItemDidPlayToEndTime (see observePlayback) —
        // a remaining-time heuristic here would also fire when the user scrubs near the end.
        MediaPlayerCoordinator.handlePlaybackChange(playing: model.isPlaying, rate: model.player.rate, position: elapsed, duration: total)
    }
    
    @MainActor func removeTimeObserver() {
        guard let timeObserver = model.timeObserver else { return }
        model.player.removeTimeObserver(timeObserver)
        model.timeObserver = nil
    }

    @MainActor
    func observeSharedAudio() {
        guard let coordinator = model.coordinator else { return }
        model.sharedAudioTask?.cancel()
        // Observations delivers every change for the lifetime of the task — unlike
        // withObservationTracking, which fires once and silently died whenever an
        // early exit skipped the re-arm.
        model.sharedAudioTask = Task { @MainActor [weak self] in
            for await audioId in Observations({ coordinator.sharedAudioId }) {
                guard let self else { return }
                await self.handleSharedAudio(audioId)
            }
        }
    }

    @MainActor
    private func handleSharedAudio(_ audioId: UUID?) async {
        guard let audioId, audioId != model.currentItem?.id else { return }
        guard let item = itemController.itemSync(for: audioId) else { return }
        await add(audio: [item], replace: true)
    }
}
