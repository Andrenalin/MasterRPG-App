// @copyright André Trettin

import AVFoundation
import Combine
import CoreRPG
import SwiftUI

@MainActor @Observable
public final class AudioPlayerModel: Sendable {
    
    // MARK: player
    public var showPlayerToolBar: Bool = false
    var isPlaying: Bool = false
    var playerTime: PlayerTime = .zero
    var currentTime: Double {
        player.currentTime().seconds
    }
    var volume: Double = 0.25 {
        didSet { player.volume = Float(volume) }
    }
    var isMuted: Bool {
        volume == 0
    }
    var isPlaybackComplete = false
    /// Whether the app wants audio to play: set by `play()`, cleared by `pause()` and when the
    /// playlist ends. An interruption pauses the player without clearing it, so it tells what
    /// to resume; `isPlaying` is updated by an observer task and may or may not have seen the
    /// system's pause when the interruption is reported. See CODE_AUDIT_21 §5.28.
    @ObservationIgnored var wantsPlayback = false

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
    var isInitialized = false
    var player = AVPlayer()

    private(set) var subscriptions = Set<AnyCancellable>()
    var timeObserver: Any? = nil
    @ObservationIgnored var sharedAudioTask: Task<Void, Never>?
    @ObservationIgnored var seekTask: Task<Void, Never>?
    /// The running `loadAndPlay`, replaced (and cancelled) by the next one. See CODE_AUDIT_21 §3.4.
    @ObservationIgnored var loadAndPlayTask: Task<Void, Never>?
    
    func add(subscriptions: Set<AnyCancellable>) {
        self.subscriptions = self.subscriptions.union(subscriptions)
    }

    /// Ends the playback observers, which are bound to the player they were created for.
    func removeSubscriptions() {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
    }

}
