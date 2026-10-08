// @copyright André Trettin

import AVFoundation
import Combine
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

}
