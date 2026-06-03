// @copyright André Trettin

import CoreRPG
import AVFoundation
import Combine
import GroupActivities
import OSLog
import Observation

final class AudioController {
    @MainActor
    init(itemController: ItemController, model: AudioPlayerModel) {
        self.itemController = itemController
        self.model = model
    }
    
    let itemController: ItemController
    let model: AudioPlayerModel
    
    @MainActor func prewarm() {
        initAudioSessionEngine()
    }
}

// MARK: - Player controls

extension AudioController {
    @MainActor
    func play() {
        model.player.play()
    }

    @MainActor
    func pause() {
        model.player.pause()
    }
    
    @MainActor
    func toggle() {
        model.showPlayerToolBar = true
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
    func togglePlay(id: UUID? = nil, triggerPlay: Bool = true) {
        if let id, id != model.currentId {
            if model.isPlaying {
                pause()
            }
            model.set(currentId: id)
            Task { @MainActor in
                await preparePlay(id: id, triggerPlay: triggerPlay)
            }
            return
        }
        if triggerPlay { toggle() }
    }
    
    @MainActor
    func skipToCurrentItem(offsetBy offset: Int) {
        guard let currentIndex = model.currentIndex else { return }
        let newIndex = currentIndex + offset
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
}

// MARK: - Playlist

extension AudioController {
    func add(audio models: [AudioModel], replace: Bool = false) async {
        if replace {
            await MainActor.run {
                model.playList = []
                model.isPlaybackComplete = false
            }
        }

        for item in models {
            guard let playItem = await audioAsset(for: item) else { continue }
            await MainActor.run {
                model.playList.append(playItem)
            }
        }
    }
    
    private func audioAsset(for item: AudioModel) async -> PlaylistItem? {
        guard let fileUrl = item.fileUrl, let fileUrlDataController = itemController.fileUrlDataController else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            _ = await fileUrlDataController.fileDownloaded(for: fileUrl)
            audioAsset = try await fileUrlDataController.url(for: fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                // Use ResourceCache for better performance
                let key = "audio.\(item.id.uuidString)"
                let data = try await ResourceCache.shared.load(key: key, from: url)
                let fileExtension = url.pathExtension
                let tempUrl = URL.temporaryDirectory.appending(path: item.id.uuidString).appendingPathExtension(fileExtension)
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                let description = item.description.isEmpty ? "MasterRPG" : item.description
                return PlaylistItem(id: item.id, url: asset.url, title: item.name, artist: description, duration: duration)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from file url: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if audioAsset == nil, let data = fileUrl.data {
                let tempUrl = URL.temporaryDirectory.appending(path: item.id.uuidString).appendingPathExtension(itemController.config.filenameExtension)
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                let description = item.description.isEmpty ? "MasterRPG" : item.description
                return PlaylistItem(id: item.id, url: asset.url, title: item.name, artist: description, duration: duration)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from data: \(error.localizedDescription, privacy: .public)")
        }
        return audioAsset
    }
    
    @MainActor func loadAndPlay(id: UUID) {
        // If item is already in playlist, just play it
        guard !model.playList.contains(where: { $0.id == id }) else {
            togglePlay(id: id)
            return
        }
        // Item not in playlist, load it first
        let models = [itemController.itemOrEmpty(for: id)]
        guard !models.isEmpty else { return }
        Task {
            await add(audio: models, replace: true)
            // After loading, set it as current and play
            model.set(currentId: id)
            await preparePlay(id: id)
        }
    }

    @MainActor func removeAudio(id: UUID) {
        if model.currentId == id && model.isPlaying {
            togglePlay()
        }
        guard let index = model.playList.firstIndex(where: { $0.id == id }) else { return }
        model.playList.remove(at: index)
    }

}

extension AudioController {
    @MainActor
    func preparePlay(id: UUID, triggerPlay: Bool = true) async {
        initAudioSessionEngine()
        if model.currentId != id {
            model.set(currentId: id)
        }
        // Must set coordinator ID before replacing the item — the AVPlayerPlaybackCoordinator
        // calls identifierFor(_:) during replaceCurrentItem, and needs the UUID already set.
        // Without this order the coordinator gets a random UUID on first play (works second time
        // only because sharedAudioId is already populated from the previous call).
        await model.coordinator?.coordinatePlayback(of: id)
        await replaceCurrentItem()
        if triggerPlay { play() }
    }
    
    func replaceCurrentItem() async {
        guard let currentItem = await model.currentItem, let index = await model.currentIndex else { return }

        let playerItem = AVPlayerItem(url: currentItem.url)
        await model.player.replaceCurrentItem(with: playerItem)
        await MediaPlayerCoordinator.handleItemChange(item: currentItem, index: index, count: model.playList.count)
        Task { @MainActor in
            Logger.audioController.debug("🎧 \(currentItem.title, privacy: .public) -> \(currentItem.artist, privacy: .public)  enqueued for playback.")
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
        model.player.volume = Float(model.volume)
        model.isInitialized = true
    }

    @MainActor func observePlayback() {
        guard model.subscriptions.isEmpty else { return }

        var subscriptions: Set<AnyCancellable> = []
        model.player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.model.isPlaying = status == .playing
                }
            }
            .store(in: &subscriptions)

        var notifications: Set<AnyCancellable> = []
        NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .map { _ in true }
            .sink { isPlaybackComplete in
                Task { @MainActor in
                    // we could do a reset or something else
                    // maybe shutdown the audio session?
                }
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
        // Using nil queue - callback will be on player's internal queue, then hop to MainActor
        model.timeObserver = model.player.addPeriodicTimeObserver(forInterval: timeInterval, queue: nil) { [weak self] time in
            Task { @MainActor [weak self] in
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
        
        if let model = itemController.itemSync(for: audioId) {
            Task {
                await add(audio: [model], replace: true)
            }
        }
        observeSharedAudio()
    }

    @MainActor func resetPlaylist(complete: Bool) {
        guard let currentIndex = model.currentIndex else { return }
        if currentIndex < model.playList.count - 1 {
            togglePlay(id: model.playList[currentIndex + 1].id)
        } else if model.repeatPlayList, model.playList.count > 1 {
            togglePlay(id: model.playList[0].id)
        } else {
            model.isPlaybackComplete = complete
        }
    }
}

// MARK: - AudioPlayerSessionDelegate

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
