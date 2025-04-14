// @copyright André Trettin

import AVFoundation
import Foundation
import MediaPlayer

/// Types of remote commands.
enum RemoteCommand {
    case pause, play, nextTrack, previousTrack
    case skipForward(TimeInterval)
    case skipBackward(TimeInterval)
    case changePlaybackPosition(TimeInterval)
}

/// The behavior of an object that handles remote commands.
protocol RemoteCommandHandler: AnyObject {
    func performRemoteCommand(_: RemoteCommand)
}

struct MediaPlayerCoordinator {
    static func handleItemChange(item: PlaylistItem?, index: Int, count: Int) {
        Task { @MainActor in
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
                newNowPlayingInfo[MPMediaItemPropertyArtist] = "MasterRPG"
                //            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { size -> AKImage in return image })
                
                newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
                newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
                
                // Reinitialize information about the playback position.
                newNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = nil
                newNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
                newNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = nil
                newNowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = nil
            }
            let update = newNowPlayingInfo
            nowPlayingInfoCenter.nowPlayingInfo = update
        }
    }
    
    /// Updates the information in the MPNowPlayingInfoCenter when the playback rate or position changes.
    static func handlePlaybackChange(playing: Bool, rate: Float, position: Double, duration: Double) {
        Task { @MainActor in
            let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
            var updatedNowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()
            
            updatedNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Float(duration)
            updatedNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Float(position)
            updatedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
            updatedNowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            
            let update = updatedNowPlayingInfo
            nowPlayingInfoCenter.nowPlayingInfo = update
        }
    }
    
    static func handleRemoteCommands(using handler: RemoteCommandHandler) {
        let commandCenter = MPRemoteCommandCenter.shared()
        
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
