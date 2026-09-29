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

    /// How many tracks are copied/loaded at the same time. Unbounded fan-out used to queue
    /// every track of a large playlist behind the file-coordination limiter at once.
    /// See CODE_AUDIT_18 §5.7.
    private static let maxConcurrentTrackLoads = 3

    @MainActor
    func add(audio models: [AudioModel], replace: Bool = false) async {
        if replace {
            // The dropped entries' temp copies would otherwise stay until the OS purges the
            // temp folder (`removeAudio` is the only other place that frees them).
            // See CODE_AUDIT_15 §5.13.
            for item in model.playList {
                try? FileManager.default.removeItem(at: item.url)
            }
            model.playList = []
            model.isPlaybackComplete = false
            model.playListGeneration += 1
        }
        // Another replacement can interleave during the loading await below (shared-audio
        // observation, `loadAndPlay`, a game reveal). Items loaded for a playlist that has
        // been replaced since are discarded, not appended. See CODE_AUDIT_18 §3.7.
        let generation = model.playListGeneration

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
            var pending = requests.enumerated().makeIterator()
            for _ in 0..<Self.maxConcurrentTrackLoads {
                guard let (index, request) = pending.next() else { break }
                group.addTask { (index, await self.audioAsset(for: request)) }
            }
            var results = [Int: PlaylistItem?]()
            for await (index, playItem) in group {
                results[index] = playItem
                if let (nextIndex, nextRequest) = pending.next() {
                    group.addTask { (nextIndex, await self.audioAsset(for: nextRequest)) }
                }
            }
            return results
        }
        let playItems = requests.indices.compactMap { loaded[$0] ?? nil }
        guard model.playListGeneration == generation else {
            for item in playItems {
                try? FileManager.default.removeItem(at: item.url)
            }
            return
        }
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
            audioAsset = try await fileUrlDataController.url(for: request.fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                // Read through the coordinated copy instead of the raw path: a coordinated
                // read of an evicted iCloud file waits for its download (CODE_AUDIT_17
                // §5.21), and works unchanged for local and app-group files. The former
                // explicit `startDownloadingUbiquitousItem` step took a coordinated *write*
                // lock, didn't wait, and could fail for non-ubiquitous files.
                // See CODE_AUDIT_18 §5.7.
                //
                // Copy file-to-file: AVURLAsset streams from disk, so the track never
                // needs to be loaded into memory.
                //
                // One temp file per load: two overlapping loads of the same track used to
                // share `<id>.<ext>`, so one could delete the file the other's asset was
                // still loading. Replacing/removing a playlist entry deletes its file, and
                // a discarded load deletes its own. See CODE_AUDIT_18 §3.7 (and §7.1).
                let tempUrl = Self.temporaryTrackUrl(for: request.id, pathExtension: url.pathExtension)
                try await FileManager.default.copyItem(coordinatingAccessFrom: url, to: tempUrl)
                return try await Self.loadingRemovingOnFailure(request, from: tempUrl)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from file url: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if audioAsset == nil, let data = request.fileUrl.data {
                let tempUrl = Self.temporaryTrackUrl(for: request.id, pathExtension: itemController.config.filenameExtension)
                try data.write(to: tempUrl)
                return try await Self.loadingRemovingOnFailure(request, from: tempUrl)
            }
        } catch {
            Logger.audioController.error("Cannot read audio from data: \(error.localizedDescription, privacy: .public)")
        }
        return audioAsset
    }

    /// Loads the copied track, deleting the copy when loading fails: nothing else would ever
    /// remove it. See CODE_AUDIT_19 §7.3.
    private static func loadingRemovingOnFailure(_ request: AudioAssetRequest, from tempUrl: URL) async throws -> PlaylistItem {
        do {
            return try await PlaylistItem.loading(id: request.id, title: request.title, artist: request.artist, from: tempUrl)
        } catch {
            try? FileManager.default.removeItem(at: tempUrl)
            throw error
        }
    }

    private static func temporaryTrackUrl(for id: UUID, pathExtension: String) -> URL {
        trackDirectory
            .appending(path: "\(id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    /// The app's own folder for the temporary track copies. Emptied once per launch, on first
    /// use, before this run has created any copy: copies still present at the previous exit
    /// were never removed and piled up. See CODE_AUDIT_19 §7.3.
    private static let trackDirectory: URL = {
        let directory = URL.temporaryDirectory.appending(path: "AudioTracks", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Logger.audioController.error("Cannot create the audio track folder: \(error.localizedDescription, privacy: .public)")
        }
        return directory
    }()

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
        guard triggerPlay else { return }
        await model.audioSession?.waitUntilConfigured()
        play()
    }

    @MainActor
    func replaceCurrentItem() {
        guard let currentItem = model.currentItem, let index = model.currentIndex else { return }

        let playerItem = AVPlayerItem(url: currentItem.url)
        model.player.replaceCurrentItem(with: playerItem)
        MediaPlayerCoordinator.handleItemChange(item: currentItem, index: index, count: model.playList.count)
        Logger.audioController.debug("🎧 \(currentItem.title, privacy: .private) -> \(currentItem.artist, privacy: .private)  enqueued for playback.")
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

        // One ordered consumer per source instead of a `Task` per event, which could apply
        // `timeControlStatus` changes out of order. The tasks are wrapped in
        // `AnyCancellable`s so the existing subscription teardown cancels them.
        // See CODE_AUDIT_18 §4.2.
        let player = model.player
        // KVO publishers don't buffer and `.values` only has demand while the loop waits, so
        // a change landing mid-iteration was dropped. The buffer keeps demand open, and each
        // element is only a wake-up: the live status is read so a stale buffered value
        // never wins. See CODE_AUDIT_19 §3.3.
        let statusChanges = player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest)
        let statusTask = Task { @MainActor [weak self] in
            for await _ in statusChanges.values {
                guard let self else { return }
                self.model.isPlaying = player.timeControlStatus == .playing
            }
        }
        let endOfItemTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                // The notification fires for every AVPlayerItem in the process — match it
                // against our current item before advancing the playlist.
                guard let self,
                      let endedItem = notification.object as? AVPlayerItem,
                      let current = self.model.player.currentItem,
                      current === endedItem else { continue }
                self.resetPlaylist(complete: true)
            }
        }
        model.add(subscriptions: [AnyCancellable { statusTask.cancel() }, AnyCancellable { endOfItemTask.cancel() }])

        addTimeObserver()
    }

    @MainActor private func addTimeObserver() {
        removeTimeObserver()
        let timeInterval = CMTime(value: 1, timescale: 1)
        // Delivered on the main queue, so the update runs in order without allocating a
        // `Task` per tick. See CODE_AUDIT_18 §4.2.
        model.timeObserver = model.player.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
            assumeMainActorIsolated {
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
