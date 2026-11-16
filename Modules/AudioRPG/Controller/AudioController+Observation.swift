// @copyright André Trettin

import AVFoundation
import CoreRPG
import Observation
import OSLog
import Synchronization

// MARK: - Playback observation

/// Follows the player (status, track end, time) and the shared audio of a SharePlay session,
/// and logs what the player reports.
extension AudioController {
    @MainActor func observePlayback() {
        guard model.observationTasks.isEmpty else { return }

        // One ordered consumer per source instead of a `Task` per event, which could apply
        // `timeControlStatus` changes out of order. The tasks are wrapped in
        // model's `observationTasks`, which the player teardown cancels.
        // See CODE_AUDIT_18 §4.2, CODE_AUDIT_26 §4.10.
        let player = model.player
        // The KVO stream buffers, so a change landing mid-iteration is not dropped, and each
        // element is only a wake-up: the live status is read so a stale buffered value
        // never wins. See CODE_AUDIT_19 §3.3.
        let statusChanges = Self.changes(of: \.timeControlStatus, on: player)
        let statusTask = Task { @MainActor [weak self] in
            for await _ in statusChanges {
                guard let self else { return }
                self.model.isPlaying = player.timeControlStatus == .playing
                Self.logPlaybackStatus(of: player)
            }
        }
        // A track that cannot be played never changes `timeControlStatus`; only its item says why.
        let itemStatusChanges = Self.changes(of: \.currentItem?.status, on: player)
        let itemStatusTask = Task { @MainActor in
            for await status in itemStatusChanges where status == .failed {
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
                self.advanceAfterTrackEnd(complete: true)
            }
        }
        model.add(observationTasks: [statusTask, itemStatusTask, endOfItemTask])

        addTimeObserver()
    }

    /// The values a key path of the player takes, starting with the current one, without repeats.
    /// A buffered stream: unlike a Combine KVO publisher it keeps the newest values while the
    /// consumer is busy. Ends (and stops observing) when the consumer's task is cancelled.
    @MainActor private static func changes<Value: Sendable & Equatable>(
        of keyPath: KeyPath<AVPlayer, Value>,
        on player: AVPlayer
    ) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let last = Mutex<Value?>(nil)
            // The value is read from the player: `change.newValue` is `nil` for an Objective-C
            // enum such as `timeControlStatus`, so every change was dropped and `isPlaying`
            // never turned true.
            let observation = KeyValueObservationBox(player.observe(keyPath, options: [.initial]) { observed, _ in
                let value = observed[keyPath: keyPath]
                let isRepeat = last.withLock { previous in
                    defer { previous = value }
                    return previous == value
                }
                if !isRepeat { continuation.yield(value) }
            })
            continuation.onTermination = { _ in observation.invalidate() }
        }
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

    @MainActor func updateCurrentTime(time: CMTime) {
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
}

/// Carries an `NSKeyValueObservation` into the stream's `@Sendable` termination handler; it is
/// only ever invalidated, which is thread-safe.
private final class KeyValueObservationBox: @unchecked Sendable {
    private let observation: NSKeyValueObservation

    init(_ observation: NSKeyValueObservation) {
        self.observation = observation
    }

    func invalidate() {
        observation.invalidate()
    }
}
