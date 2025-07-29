// @copyright André Trettin

import AVFoundation
import Combine
import SwiftUI

@MainActor @Observable
public final class AudioPlayerModel {
    
    // MARK: player
    public var showPlayerToolBar: Bool = false
    var isPlaying: Bool = false
    var playerTime: PlayerTime = .zero
    var currentTime: Double {
        player.currentTime().seconds
    }
    var volume: Float = 0.25 {
        didSet { player.volume = volume }
    }
    var isPlaybackComplete = false

    // MARK: player list
    var playList: [PlaylistItem] = []
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
//    var coordinator: AudioListenerCoordinator?
    var isInitialized = false
    var player = AVPlayer()

    private(set) var subscriptions = Set<AnyCancellable>()
    var timeObserver: Any? = nil
    
    func add(subscriptions: Set<AnyCancellable>) {
        self.subscriptions = self.subscriptions.union(subscriptions)
    }

}
