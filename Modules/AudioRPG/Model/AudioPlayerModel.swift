// @copyright André Trettin

import AVFoundation
import CoreRPG
import SwiftUI

@MainActor @Observable
public final class AudioPlayerModel: Sendable {
    
    // MARK: player
    public var showPlayerToolBar: Bool = false
    var isPlaying: Bool = false
    var playerTime: PlayerTime = .zero
    /// The player's position right now. Views read `playerTime.elapsedSeconds` instead, which
    /// is observed.
    var currentTime: Double {
        player.currentTime().seconds
    }
    /// The volume a new player starts at, and the one a mute restores when none was set before.
    static let defaultVolume = 0.25
    var volume: Double = AudioPlayerModel.defaultVolume {
        didSet {
            player.volume = Float(volume)
            // Every audible level is the one a later unmute returns to.
            if volume > 0 { previousVolume = volume }
        }
    }
    /// The volume before the last mute, shared by every bar so a mute in one surface restores
    /// the right level in another. See CODE_AUDIT_Audio2 §5.17.
    @ObservationIgnored var previousVolume = AudioPlayerModel.defaultVolume
    var isMuted: Bool {
        volume == 0
    }
    var isPlaybackComplete = false
    /// Whether the app wants audio to play: set by `play()`, cleared by `pause()` and when the
    /// playlist ends. An interruption pauses the player without clearing it, so it tells what
    /// to resume; `isPlaying` is updated by an observer task and may or may not have seen the
    /// system's pause when the interruption is reported. See CODE_AUDIT_21 §5.28.
    @ObservationIgnored var wantsPlayback = false
    /// Bumped by every pause and interruption: whoever resumes playback after an await compares
    /// it with the value it read before, so a pause that came in between is not overridden by
    /// a play that was already on its way. See CODE_AUDIT_Audio2 §3.3.
    @ObservationIgnored var playbackGeneration = 0

    // MARK: player list
    var playList: [PlaylistItem] = []
    /// Bumped whenever the playlist is replaced, so an `add` whose loading straddled a
    /// newer replacement discards its now-stale items instead of mixing them in.
    /// See CODE_AUDIT_18 §3.7.
    var playListGeneration = 0
    var currentItem: PlaylistItem?
    var currentIndex: Int? {
        guard let currentItem else { return nil }
        return playList.firstIndex(of: currentItem)
    }
    var currentId: UUID? {
        currentItem?.id
    }
    var hasNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex < (playList.count - 1)
    }
    var hasPrev: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }
    
    var repeatPlayList = false

    /// The item the current playlist was started from (a playlist item or a single audio), as set
    /// by a game play. A game loop asks everyone to play this item again: the tracks alone are
    /// not enough, a playlist item of several tracks has no file itself.
    @ObservationIgnored var playListRootId: UUID?

    /// Offers a remote command (lock screen, AirPods, headphone buttons) to the game before the
    /// controller acts on it: `true` means the command was handed to the running game, which
    /// plays, pauses or skips on every device, this one included. Set once by `AudioRootModel`.
    @ObservationIgnored var remoteCommandRouter: (@MainActor (RemoteCommand) -> Bool)?

    /// Whether a game runs: on a player's device the game master's commands drive the playlist
    /// (a loop, the next track), so the local Repeat toggle must not act on its own. Set once by
    /// `AudioRootModel`.
    @ObservationIgnored var isGameRunning: @MainActor () -> Bool = { false }

    /// Told about the new coordinator after a media-services reset replaced the audio engine, so
    /// a running SharePlay session coordinates the new player. See CODE_AUDIT_Audio2 §5.9.
    @ObservationIgnored var coordinatorDidChange: (@MainActor (AudioListenerCoordinator) -> Void)?

    /// Set on the game master's device while a game runs. Told the playlist item and the track
    /// whenever a track starts here, whatever started it (a play, next, the end of the track
    /// before it), so the game can send the next track to the players ahead of its play.
    @ObservationIgnored var trackStartHandler: (@MainActor (_ rootId: UUID, _ trackId: UUID) -> Void)?

    /// Set on the game master's device while a game runs. A loop then does not restart the
    /// playlist on this device alone but hands the play command to the game, which plays it
    /// again on every device, this one included. Without a game it is `nil` and the loop
    /// restarts locally. It must never capture a SwiftUI view.
    @ObservationIgnored var loopReplayHandler: (@MainActor (NetworkCodableDataType) -> Void)?

    
    func set(currentId: UUID) {
        currentItem = playList.first(where: { $0.id == currentId })
    }
    
    // MARK: Internal
    var audioSession: AudioPlayerSession?
    var coordinator: AudioListenerCoordinator?
    /// Tests set it; `nil` asks the coordinator.
    @ObservationIgnored var sharedPlaybackOverride: Bool?
    /// Whether this player's transport actions reach other devices (a SharePlay session with
    /// other participants). Route changes and interruptions are local events and must not use
    /// the transport then. See CODE_AUDIT_28 §3.2.
    var isPlaybackShared: Bool {
        sharedPlaybackOverride ?? coordinator?.hasOtherParticipants ?? false
    }
    var isInitialized = false
    var player = AVPlayer()

    /// The tasks that follow the player (status, track end). Cancelled with the player they watch.
    private(set) var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored var timeObserver: Any? = nil
    @ObservationIgnored var seekTask: Task<Void, Never>?
    /// The running `loadAndPlay`, replaced (and cancelled) by the next one. See CODE_AUDIT_21 §3.4.
    @ObservationIgnored var loadAndPlayTask: Task<Void, Never>?
    /// The background load of the tracks behind the one a game play started with. See
    /// `GameController.loadRemainingTracks`.
    @ObservationIgnored var remainingTracksTask: Task<Void, Never>?
    
    func add(observationTasks: [Task<Void, Never>]) {
        self.observationTasks.append(contentsOf: observationTasks)
    }

    /// Ends the playback observers, which are bound to the player they were created for.
    func removeObservationTasks() {
        observationTasks.forEach { $0.cancel() }
        observationTasks = []
    }

}
