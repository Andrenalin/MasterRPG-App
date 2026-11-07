// @copyright André Trettin

import AVFoundation
import Foundation
import MediaPlayer

#if os(iOS) || os(macOS)
import AppIntents
#endif

/// Types of remote commands.
///
/// `skipForward`/`skipBackward` were removed: `handleRemoteCommands` disables both
/// commands at the source (`skipForwardCommand.isEnabled = false`), so they could never fire.
enum RemoteCommand {
    case pause, play, togglePlayPause, nextTrack, previousTrack
    case changePlaybackPosition(TimeInterval)
}

/// The behavior of an object that handles remote commands.
/// Sendable: MPRemoteCommandCenter may invoke targets from outside the main actor;
/// implementations dispatch to their own isolation (see AudioController).
protocol RemoteCommandHandler: AnyObject, Sendable {
    func performRemoteCommand(_: RemoteCommand)
}

struct MediaPlayerCoordinator {
    /// What the system last got for the playback position. The system extrapolates the position
    /// from the elapsed time and the rate, so only a change of state or a jump is written.
    private struct PlaybackSnapshot {
        let playing: Bool
        let rate: Float
        let position: Double
        let duration: Double
        let date: Date
    }

    @MainActor private static var lastPlayback: PlaybackSnapshot?
    /// How far the position may differ from the extrapolated one before it is written again.
    private static let positionTolerance: TimeInterval = 1.5

    /// Resets the now-playing information for a new current item (or none). @MainActor and
    /// synchronous: callers are already on the main actor, and a Task per call is pure churn.
    /// `handlePlaybackChange` is the one the time observer calls every second.
    @MainActor
    static func handleItemChange(item: PlaylistItem?, index: Int, count: Int) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        // The info is rebuilt below: the next playback tick writes the position again.
        lastPlayback = nil
#if os(macOS)
        if item == nil {
            nowPlayingInfoCenter.playbackState = .stopped
        }
#endif
        var newNowPlayingInfo = [String: Any]()

        // Reinitialize the information unless there is a current item.
        if let currentItem = item {
            newNowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()

            // Update information about the item.
            newNowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            newNowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
            newNowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = currentItem.url
            newNowPlayingInfo[MPMediaItemPropertyTitle] = currentItem.title
            newNowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentItem.subtitle
            newNowPlayingInfo[MPMediaItemPropertyArtist] = PlaylistItem.defaultArtistName

            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = count

#if os(iOS) || os(macOS)
            // Lets Siri act on "the track that is playing". See CODE_AUDIT_AppIntents §4.3.
            if #available(iOS 27, macOS 27, *),
               let identifier = MPAppEntityIdentifier(
                entityIdentifier: EntityIdentifier(for: AudioEntity.self, identifier: currentItem.id)
               ) {
                newNowPlayingInfo[MPNowPlayingInfoPropertyAppEntityIdentifiers] = [identifier]
            }
#endif

            // Reinitialize information about the playback position.
            newNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = nil
        }
        nowPlayingInfoCenter.nowPlayingInfo = newNowPlayingInfo
    }

    /// Updates the information in the MPNowPlayingInfoCenter when the playback rate, the
    /// duration or the position (a seek) changes. Called once per second, but the system keeps
    /// time itself, so an unchanged state is not written again. See CODE_AUDIT_Audio2 §7.5.
    @MainActor
    static func handlePlaybackChange(playing: Bool, rate: Float, position: Double, duration: Double) {
        let now = Date.now
        if let last = lastPlayback, last.playing == playing, last.rate == rate, last.duration == duration {
            let expected = last.position + (playing ? Double(rate) * now.timeIntervalSince(last.date) : 0)
            if abs(position - expected) < positionTolerance { return }
        }
        lastPlayback = PlaybackSnapshot(playing: playing, rate: rate, position: position, duration: duration, date: now)

        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
#if os(macOS)
        // macOS cannot derive the state from an audio session: Control Center, the menu bar and
        // the media keys need it. See CODE_AUDIT_Audio2 §4.2.
        nowPlayingInfoCenter.playbackState = playing ? .playing : .paused
#endif
        var updatedNowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()

        updatedNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Float(duration)
        updatedNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Float(position)
        updatedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        updatedNowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        nowPlayingInfoCenter.nowPlayingInfo = updatedNowPlayingInfo
    }

    @MainActor
    static func handleRemoteCommands(using handler: RemoteCommandHandler) {
        let commandCenter = MPRemoteCommandCenter.shared()

        // addTarget accumulates: after a media-services reset this runs again, and
        // without the removes every remote press would be handled twice.
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.pauseCommand.addTarget { [weak handler] _ in
            guard let handler else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.pause)
            return .success
        }
        
        commandCenter.playCommand.addTarget { [weak handler] _ in
            guard let handler else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.play)
            return .success
        }
        
        // The play/pause media key (and some headsets) send the toggle, not play or pause.
        commandCenter.togglePlayPauseCommand.addTarget { [weak handler] _ in
            guard let handler else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.togglePlayPause)
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak handler] _ in
            guard let handler else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.nextTrack)
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak handler] _ in
            guard let handler else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.previousTrack)
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak handler] event in
            guard let handler, let event = event as? MPChangePlaybackPositionCommandEvent else { return .noActionableNowPlayingItem }
            handler.performRemoteCommand(.changePlaybackPosition(event.positionTime))
            return .success
        }
    }
}
