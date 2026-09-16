// @copyright André Trettin

import AVFoundation
import Foundation
import MediaPlayer

/// Types of remote commands.
///
/// `skipForward`/`skipBackward` were removed: `handleRemoteCommands` disables both
/// commands at the source (`skipForwardCommand.isEnabled = false`), so they could never fire.
enum RemoteCommand {
    case pause, play, nextTrack, previousTrack
    case changePlaybackPosition(TimeInterval)
}

/// The behavior of an object that handles remote commands.
/// Sendable: MPRemoteCommandCenter may invoke targets from outside the main actor;
/// implementations dispatch to their own isolation (see AudioController).
protocol RemoteCommandHandler: AnyObject, Sendable {
    func performRemoteCommand(_: RemoteCommand)
}

struct MediaPlayerCoordinator {
    /// @MainActor and synchronous — callers are already on the main actor; spawning
    /// a Task per call (once per second from the time observer) is pure churn.
    @MainActor
    static func handleItemChange(item: PlaylistItem?, index: Int, count: Int) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var newNowPlayingInfo = [String: Any]()

        // Reinitialize the information unless there is a current item.
        if let currentItem = item {
            newNowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()

            // Update information about the item.
            newNowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            newNowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
            newNowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = currentItem.url
            newNowPlayingInfo[MPMediaItemPropertyTitle] = currentItem.title
            newNowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentItem.artist
            newNowPlayingInfo[MPMediaItemPropertyArtist] = PlaylistItem.defaultArtistName

            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = count

            // Reinitialize information about the playback position.
            newNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nil
            newNowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = nil
        }
        nowPlayingInfoCenter.nowPlayingInfo = newNowPlayingInfo
    }

    /// Updates the information in the MPNowPlayingInfoCenter when the playback rate or position changes.
    @MainActor
    static func handlePlaybackChange(playing: Bool, rate: Float, position: Double, duration: Double) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
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
