// @copyright André Trettin

import CoreRPG
import AVFoundation
import Combine
import GroupActivities
import OSLog
import Observation

final class AudioController: Sendable {
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
                Task {
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
            Task {
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

    // Stays nonisolated (not @MainActor) — the scrubber stores this as a
    // @Sendable closure so it must remain callable from any isolation context.
    func skip(to offset: TimeInterval) {
        Task { @MainActor in
            // Cancel any in-flight seek before starting a new one — a rapid
            // sequence of calls (e.g. debounced scrubber updates) should only
            // ever land on the last requested position. `preferredTimescale:
            // 600` avoids snapping every seek to the nearest whole second.
            // See CODE_AUDIT_Audio §7.1.
            model.seekTask?.cancel()
            model.seekTask = Task {
                await model.player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
            }
        }
    }

}

// MARK: - Playlist

extension AudioController {
    /// Snapshot of the fields the @concurrent loading code needs, extracted on the
    /// MainActor so no live AudioModel instance crosses the isolation boundary.
    private struct AudioAssetRequest: Sendable {
        let id: UUID
        let title: String
        let artist: String
        let fileUrl: FileUrl
    }

    @MainActor
    func add(audio models: [AudioModel], replace: Bool = false) async {
        if replace {
            model.playList = []
            model.isPlaybackComplete = false
        }

        let requests = models.compactMap { item -> AudioAssetRequest? in
            guard let fileUrl = item.fileUrl else { return nil }
            return AudioAssetRequest(
                id: item.id,
                title: item.name,
                artist: item.description.isEmpty ? PlaylistItem.defaultArtistName : item.description,
                fileUrl: fileUrl
            )
        }

        // Load concurrently (each request is an independent file copy + duration
        // load off the main actor), then reassemble in the original request order.
        let loaded = await withTaskGroup(of: (Int, PlaylistItem?).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask { (index, await self.audioAsset(for: request)) }
            }
            var results = [Int: PlaylistItem?]()
            for await (index, playItem) in group {
                results[index] = playItem
            }
            return results
        }
        let playItems = requests.indices.compactMap { loaded[$0] ?? nil }
        // Single mutation: one observation change instead of one per item.
        model.playList.append(contentsOf: playItems)
    }

    /// @concurrent: file copies and asset loading must not run on the main actor —
    /// nonisolated async would inherit the (main actor) caller's isolation here.
    @concurrent
    private func audioAsset(for request: AudioAssetRequest) async -> PlaylistItem? {
        guard let fileUrlDataController = itemController.fileUrlDataController else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            _ = await fileUrlDataController.fileDownloaded(for: request.fileUrl)
            audioAsset = try await fileUrlDataController.url(for: request.fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                // Copy file-to-file: AVURLAsset streams from disk, so the track never
                // needs to be loaded into memory.
                //
                // Stable per-item filename (no per-play UUID suffix) so replaying —
                // or switching playlists back and forth over — the same track
                // overwrites its own temp copy instead of leaking a fresh file every
                // time. See CODE_AUDIT §7.1.
                let tempUrl = URL.temporaryDirectory
                    .appending(path: request.id.uuidString)
                    .appendingPathExtension(url.pathExtension)
                let fileManager = FileManager.default
                // `copyItem` throws if the destination already exists (unlike
                // `Data.write(to:)` below), so clear out a previous play's copy first.
                try? fileManager.removeItem(at: tempUrl)
                try fileManager.copyItem(at: url, to: tempUrl)
                return try await PlaylistItem.loading(id: request.id, title: request.title, artist: request.artist, from: tempUrl)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from file url: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if audioAsset == nil, let data = request.fileUrl.data {
                let tempUrl = URL.temporaryDirectory
                    .appending(path: request.id.uuidString)
                    .appendingPathExtension(itemController.config.filenameExtension)
                try data.write(to: tempUrl)
                return try await PlaylistItem.loading(id: request.id, title: request.title, artist: request.artist, from: tempUrl)
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
        // Free the item's temp copy along with its playlist entry — its
        // filename is stable per item (see `audioAsset(for:)`), so nothing
        // else will reclaim it once it's gone from the list. See CODE_AUDIT §7.1.
        try? FileManager.default.removeItem(at: model.playList[index].url)
        model.playList.remove(at: index)
        // The removed item may have been the current-but-paused track: `currentItem`
        // is a stored reference, not derived from `playList`, so leaving it pointing
        // at a row no longer in the list would permanently break `currentIndex`
        // (and therefore hasNext/hasPrev). Clear it explicitly instead. See CODE_AUDIT_Audio §5.3.
        if model.currentId == id {
            model.currentItem = nil
        }
    }

}

extension AudioController {
    @MainActor
    func preparePlay(id: UUID, triggerPlay: Bool = true) async {
        initAudioSessionEngine()
        // A prior playlist-completion (see resetPlaylist) must not stick past the
        // track it applied to — otherwise every later toggle() treats playback as
        // "finished" and restarts from 0:00 instead of resuming. See CODE_AUDIT_Audio §5.2.
        model.isPlaybackComplete = false
        if model.currentId != id {
            model.set(currentId: id)
        }
        // Must set coordinator ID before replacing the item — the AVPlayerPlaybackCoordinator
        // calls identifierFor(_:) during replaceCurrentItem, and needs the UUID already set.
        // Without this order the coordinator gets a random UUID on first play (works second time
        // only because sharedAudioId is already populated from the previous call).
        model.coordinator?.coordinatePlayback(of: id)
        replaceCurrentItem()
        if triggerPlay { play() }
    }

    @MainActor
    func replaceCurrentItem() {
        guard let currentItem = model.currentItem, let index = model.currentIndex else { return }

        let playerItem = AVPlayerItem(url: currentItem.url)
        model.player.replaceCurrentItem(with: playerItem)
        MediaPlayerCoordinator.handleItemChange(item: currentItem, index: index, count: model.playList.count)
        Logger.audioController.debug("🎧 \(currentItem.title, privacy: .public) -> \(currentItem.artist, privacy: .public)  enqueued for playback.")
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
        // Re-observe here (not in observePlayback, which early-returns on re-init):
        // after a media-services reset the coordinator is a new instance and the
        // old observation task would keep following the stale one.
        observeSharedAudio()

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
            .sink { [weak self] notification in
                // The notification fires for every AVPlayerItem in the process —
                // extract the (Sendable) identity here and match it against our
                // current item on the main actor before advancing the playlist.
                let endedItem = (notification.object as? AVPlayerItem).map(ObjectIdentifier.init)
                Task { @MainActor [weak self] in
                    guard let self, let endedItem,
                          let current = self.model.player.currentItem,
                          ObjectIdentifier(current) == endedItem else { return }
                    self.resetPlaylist(complete: true)
                }
            }
            .store(in: &notifications)

        model.add(subscriptions: subscriptions)
        model.add(subscriptions: notifications)

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

        // Track advancing is driven by AVPlayerItemDidPlayToEndTime (see observePlayback) —
        // a remaining-time heuristic here would also fire when the user scrubs near the end.
        MediaPlayerCoordinator.handlePlaybackChange(playing: model.isPlaying, rate: model.player.rate, position: time.seconds, duration: duration.seconds)
    }
    
    @MainActor private func removeTimeObserver() {
        guard let timeObserver = model.timeObserver else { return }
        model.player.removeTimeObserver(timeObserver)
        model.timeObserver = nil
    }

    @MainActor
    func observeSharedAudio() {
        guard let coordinator = model.coordinator else { return }
        model.sharedAudioTask?.cancel()
        // Observations delivers every change for the lifetime of the task — unlike
        // withObservationTracking, which fires once and silently died whenever an
        // early exit skipped the re-arm.
        model.sharedAudioTask = Task { @MainActor [weak self] in
            for await audioId in Observations({ coordinator.sharedAudioId }) {
                guard let self else { return }
                await self.handleSharedAudio(audioId)
            }
        }
    }

    @MainActor
    private func handleSharedAudio(_ audioId: UUID?) async {
        guard let audioId, audioId != model.currentItem?.id else { return }
        guard let item = itemController.itemSync(for: audioId) else { return }
        await add(audio: [item], replace: true)
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
            case .changePlaybackPosition(let offset):
                skip(to: offset)
            }
        }
    }
}

extension Logger {
    static let audioController = Logger(subsystem: subsystem, category: "AudioController")
}
