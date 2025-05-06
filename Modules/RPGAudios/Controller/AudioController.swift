// @copyright André Trettin

import AndrenalinKit
import AVKit
import Combine
import GroupActivities
import os.log
import Observation

@MainActor @Observable
final class AudioPlayerModel: Sendable {
    // UI state
    var playList: [PlaylistItem] = []
    var currentItem: PlaylistItem?
    var currentIndex = 0
    var currentId: UUID? {
        currentItem?.id
    }
    var repeatPlayList = false
    
    var isPlaying = false
    var playerTime: PlayerTime = .zero
    var currentTime: Double {
        player.currentTime().seconds
    }
    var volume: Float = 0.25 {
        didSet { player.volume = volume }
    }
    
    // internal state for the controller
    
    var audioSession: AudioPlayerSession?
    var coordinator: AudioListenerCoordinator?
    var isInitialized = false
    var isPlaybackComplete = false
    var player = AVPlayer()
    enum PlayMode {
        case local
        case share
    }
    private(set) var playMode: PlayMode = .local
    private(set) var subscriptions = Set<AnyCancellable>()
    var timeObserver: Any? = nil
    
    func add(subscriptions: Set<AnyCancellable>) {
        self.subscriptions = self.subscriptions.union(subscriptions)
    }
    
    func resetPlayMode(_ mode: PlayMode) {
        playMode = mode
    }
}

final class AudioController: Sendable {
    @MainActor
    init(root: AudioRoot) {
        self.root = root
        self.model = AudioPlayerModel()
    }

    unowned let root: AudioRoot!
    let model: AudioPlayerModel

    // MARK: Player

    @MainActor
    func togglePlay(id: UUID? = nil) {
        if let id, id != model.currentId, let index = model.playList.firstIndex(where: { $0.id == id }) {
            if model.isPlaying {
                pause()
            }
            model.currentIndex = index
            Task { @MainActor in
                await preparePlay(id: id)
            }
            return
        }
        toggle()
    }
    
    @MainActor
    func toggle() {
        if model.isPlaying {
            pause()
        } else {
            if model.isPlaybackComplete, let id = model.currentId {
                Task { @MainActor in
                    await preparePlay(id: id)
                }
            } else {
                play()
            }
        }
    }

    @MainActor
    func play() {
        model.player.play()
    }

    @MainActor
    func pause() {
        model.player.pause()
    }

    @MainActor
    func skipToCurrentItem(offsetBy offset: Int) {
        let newIndex = model.currentIndex + offset
        guard newIndex >= 0 && newIndex < model.playList.count else { return }
        let newId = model.playList[newIndex].id
        togglePlay(id: newId)
    }

    func skip(to offset: TimeInterval) {
        Task {
            await model.player.seek(to: CMTime(seconds: offset, preferredTimescale: CMTimeScale(1)))
        }
    }

    @MainActor
    func skip(by distance: TimeInterval) {
        let offset = model.currentTime + Double(distance)
        skip(to: offset)
    }

    @MainActor
    func preparePlay(id: UUID) async {
        initAudioSessionEngine()
        if model.currentId != id {
            if let index = model.playList.firstIndex(where: { $0.id == id }) {
                model.currentItem = model.playList[index]
                model.currentIndex = index
            } else {
                return
            }
        }
        switch model.playMode {
        case .share:
            let shareTask = Task { @MainActor in
                await model.coordinator?.coordinatePlayback(of: id)
                await replaceCurrentItem()
            }
            let _ = await shareTask.result
        case .local:
            await replaceCurrentItem()
        }

        configureAudioExperience()
        play()
    }

    @MainActor
    func loadAndPlay(id: UUID) {
        guard model.playList.contains(where: { $0.id != id }) else {
            togglePlay(id: id)
            return
        }
        let models = root.gameController.fetchPlaylist(id: id)
        guard !models.isEmpty else { return }
        Task {
            await addAudio(models: models, replace: true, playId: id, shouldPlay: true)
        }
    }

    // MARK: Playlist

    func addAudio(models: [AudioModel], replace: Bool = false, playId: UUID? = nil, playMode: AudioPlayerModel.PlayMode = .local, shouldPlay: Bool) async {
        let playNextId: UUID?
        if let playId, !models.contains(where: { $0.id == playId }), let firstId = models.first?.id {
            playNextId = firstId
        } else {
            playNextId = playId
        }
        if let playNextId, await model.currentId == playNextId {
            if await model.isPlaying && shouldPlay {
                return
            }
            if await model.isPlaying && !shouldPlay {
                await togglePlay()
                return
            }
        }

        if replace {
            let resetTask = Task { @MainActor in
                model.playList = []
                model.currentIndex = 0
                model.isPlaybackComplete = false
            }
            _ = await resetTask.result
        }
        for item in models {
            let loader = Task.detached { [weak self] in
                return await self?.root?.gameController.audioAsset(for: item.id)
            }
            let loaderTask = Task { @MainActor in
                guard let playItem = await loader.value else { return }
                if playItem.id == playNextId {
                    model.currentIndex = model.playList.count
                }
                model.playList.append(playItem)
            }
            _ = await loaderTask.result
        }

        await model.resetPlayMode(playMode)
        guard let playNextId else { return }
        await preparePlay(id: playNextId)
    }

    @MainActor func removeAudio(id: UUID) {
        if model.currentId == id && model.isPlaying {
            togglePlay()
        }
        guard let index = model.playList.firstIndex(where: { $0.id == id }) else { return }
        model.playList.remove(at: index)
    }

    func replaceCurrentItem() async {
        guard let currentItem = await model.currentItem else { return }

        let playerItem = AVPlayerItem(url: currentItem.url)
        await model.player.replaceCurrentItem(with: playerItem)
        await MediaPlayerCoordinator.handleItemChange(item: currentItem, index: model.currentIndex, count: model.playList.count)
        Task { @MainActor in
            Logger.audioController.debug("🎧 \(self.root.itemController.itemOrEmpty(for: currentItem.id).name, privacy: .public) enqueued for playback.")
        }
    }
}

private extension AudioController {
    @MainActor
    func initAudioSessionEngine() {
        guard !model.isInitialized else { return }
        let session = AudioPlayerSession(delegate: self)
        session.initSession()
        model.audioSession = session

        model.coordinator = AudioListenerCoordinator(playbackCoordinator: model.player.playbackCoordinator)

        MediaPlayerCoordinator.handleRemoteCommands(using: self)

        observePlayback()
        model.player.volume = model.volume
        model.isInitialized = true
    }

    @MainActor func observePlayback() {
        guard model.subscriptions.isEmpty else { return }

        var subscriptions: Set<AnyCancellable> = []
        model.player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.model.isPlaying = status == .playing
            }
            .store(in: &subscriptions)

        var notifications: Set<AnyCancellable> = []
        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .map { _ in true }
            .sink { isPlaybackComplete in
                // we could do a reset or something else
                // maybe shutdown the audio session?
            }
            .store(in: &notifications)

        model.add(subscriptions: subscriptions)
        model.add(subscriptions: notifications)
        
        observeSharedAudio()
        
        addTimeObserver()
    }

    @MainActor private func addTimeObserver() {
        removeTimeObserver()
        let timeInterval = CMTime(value: 1, timescale: 1)
        model.timeObserver = model.player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateCurrentTime(time: time)
            }
        }
    }

    @MainActor private func updateCurrentTime(time: CMTime) {
        guard let duration = model.player.currentItem?.duration else { return }
        model.playerTime = PlayerTime(elapsedTime: time.seconds, remainingTime: duration.seconds - time.seconds)

        MediaPlayerCoordinator.handlePlaybackChange(playing: model.isPlaying, rate: model.player.rate, position: time.seconds, duration: duration.seconds)
        if duration.seconds - time.seconds < 1 {
            resetPlaylist(complete: true)
        }
    }
    
    @MainActor private func removeTimeObserver() {
        guard let timeObserver = model.timeObserver else { return }
        model.player.removeTimeObserver(timeObserver)
        model.timeObserver = nil
    }

    @MainActor
    func observeSharedAudio() {
        guard let coordinator = model.coordinator else { return }
        _ = withObservationTracking {
            coordinator.sharedAudioId
        } onChange: { [weak self] in
            Task {
                await self?.checkForSharedAudio()
            }
        }
    }
    
    @MainActor
    func checkForSharedAudio() {
        guard let audioId = model.coordinator?.sharedAudioId, audioId != model.currentItem?.id else { return }
        
        let models = self.root.gameController.fetchPlaylist(id: audioId)
        Task {
            await addAudio(models: models, replace: true, playId: audioId, playMode: .share, shouldPlay: true)
        }
        observeSharedAudio()
    }

    @MainActor func resetPlaylist(complete: Bool) {
        if model.currentIndex < model.playList.count - 1 {
            togglePlay(id: model.playList[model.currentIndex + 1].id)
        } else if model.repeatPlayList, model.playList.count > 1 {
            togglePlay(id: model.playList[0].id)
        } else {
            model.isPlaybackComplete = complete
        }
    }

    /// Configures the user's intended spatial audio experience to best fit the presentation.
    /// - Parameter presentation: the requested player presentation.
    @MainActor func configureAudioExperience() {
#if os(visionOS)
        do {
            let experience: AVAudioSessionSpatialExperience
            switch model.playMode {
            case .local:
                // Set a small, focused sound stage when watching trailers.
                experience = .headTracked(soundStageSize: .small, anchoringStrategy: .automatic)
            case .share:
                // Set a large sound stage size when viewing fullscreen.
                experience = .headTracked(soundStageSize: .large, anchoringStrategy: .automatic)
            }
            try AVAudioSession.sharedInstance().setIntendedSpatialExperience(experience)
        } catch {
            Logger.audioController.error("Unable to set the intended spatial experience. \(error.localizedDescription)")
        }
#endif
    }
}

extension AudioController: AudioPlayerSessionDelegate {
    @MainActor func routeChanged() {
        if model.isPlaying {
            pause()
        }
    }

    @MainActor func beginInterruption() -> Bool {
        if model.isPlaying {
            pause()
            return true
        }
        return false
    }

    @MainActor func endInterruption(wasPlaying: Bool) {
        if wasPlaying {
            togglePlay()
        }
    }

    @MainActor
    func resetMediaService() {
        model.isInitialized = false
        initAudioSessionEngine()
    }
}

// MARK: - RemoteCommandHandler

extension AudioController: RemoteCommandHandler {
    func performRemoteCommand(_ command: RemoteCommand) {
        Task { @MainActor in
            switch command {
            case .pause:
                pause()
            case .play:
                play()
            case .nextTrack:
                skipToCurrentItem(offsetBy: 1)
            case .previousTrack:
                skipToCurrentItem(offsetBy: -1)
            case .skipForward(let distance):
                skip(by: distance)
            case .skipBackward(let distance):
                skip(by: -distance)
            case .changePlaybackPosition(let offset):
                skip(to: offset)
            }
        }
    }
}

extension Logger {
    static let audioController = Logger(subsystem: subsystem, category: "AudioController")
}
