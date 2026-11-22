// @copyright André Trettin

import CoreRPG
import AVFoundation
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
    
    /// Loads the files of audio items as playlist items. See `AudioTrackLoader`.
    @MainActor var trackLoader: AudioTrackLoader {
        AudioTrackLoader(
            fileUrlDataController: itemController.fileUrlDataController,
            filenameExtension: itemController.config.filenameExtension
        )
    }

    @MainActor func prewarm() {
        initAudioSessionEngine()
    }
}

// MARK: - Player controls

extension AudioController {
    /// Every play path ends here, so the first track can never begin under the default audio
    /// category (muted by the ring switch, no long-form routing) while the session is still
    /// being configured, and the session is activated by the first real play, not before.
    /// A pause that arrives while the session is being activated wins: the play on its way
    /// checks the intent again. See CODE_AUDIT_19 §3.5, CODE_AUDIT_20 §3.2, CODE_AUDIT_Audio2 §3.3.
    @MainActor
    func play() {
        model.wantsPlayback = true
        guard let session = model.audioSession, session.needsActivation else {
            model.player.play()
            return
        }
        let generation = model.playbackGeneration
        Task { @MainActor in
            await session.activate()
            guard model.playbackGeneration == generation, model.wantsPlayback else { return }
            model.player.play()
        }
    }

    @MainActor
    func pause() {
        model.wantsPlayback = false
        model.playbackGeneration += 1
        model.player.pause()
    }

    /// Lets other apps' audio resume when nothing plays here.
    @MainActor
    func releaseAudioSession() {
        guard !model.isPlaying, !model.wantsPlayback else { return }
        model.audioSession?.deactivate()
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
    func togglePlay(id: UUID? = nil) {
        if let id, id != model.currentId {
            if model.isPlaying {
                pause()
            }
            model.set(currentId: id)
            Task {
                await preparePlay(id: id)
            }
            return
        }
        toggle()
    }
    
    @MainActor
    func skip(offsetBy offset: Int) {
        guard let currentIndex = model.currentIndex else { return }
        let newIndex = currentIndex + offset
        guard newIndex >= 0 && newIndex < model.playList.count else { return }
        let newId = model.playList[newIndex].id
        togglePlay(id: newId)
    }

    /// Seeks the current item to `offset` seconds. A newer seek replaces one still running, so a
    /// rapid sequence (a scrubber drag) only lands on the last position; `preferredTimescale: 600`
    /// avoids snapping every seek to the nearest whole second. See CODE_AUDIT_Audio §7.1.
    @MainActor
    func seek(to offset: TimeInterval) {
        model.seekTask?.cancel()
        model.seekTask = Task {
            await model.player.seek(to: Self.seekTime(offset))
            guard !Task.isCancelled else { return }
            // A paused player has no tick to show the new position.
            updateCurrentTime(time: model.player.currentTime())
        }
    }

    /// `seek(to:)` that returns once the player is at `offset`, for a start that must not play
    /// from the beginning first.
    @MainActor
    func seekAndWait(to offset: TimeInterval) async {
        model.seekTask?.cancel()
        await model.player.seek(to: Self.seekTime(offset))
        updateCurrentTime(time: model.player.currentTime())
    }

    static func seekTime(_ offset: TimeInterval) -> CMTime {
        CMTime(seconds: offset, preferredTimescale: seekTimescale)
    }

    private static let seekTimescale: CMTimeScale = 600

}

// MARK: - Playlist

extension AudioController {
    /// Returns whether the loaded tracks were added. `false` means a newer replacement took
    /// the playlist while they loaded and they were discarded: the caller must not go on to
    /// select or play a track of this load, it is not in the playlist. See CODE_AUDIT_21 §3.4.
    @MainActor
    @discardableResult
    func add(audio models: [AudioModel], replace: Bool = false) async -> Bool {
        if replace {
            // The dropped entries' temp copies would otherwise stay until the OS purges the
            // temp folder (`removeAudio` is the only other place that frees them).
            // See CODE_AUDIT_15 §5.13.
            for item in model.playList {
                try? FileManager.default.removeItem(at: item.url)
            }
            model.playList = []
            // `currentItem` is a stored reference to a row of the dropped list: left behind it
            // points at a deleted track and breaks `currentIndex`, `hasNext` and `hasPrev` when
            // the new load fails or is discarded. See CODE_AUDIT_26 §5.99.
            model.currentItem = nil
            model.isPlaying = false
            // A game play names the new playlist's root right after this.
            model.playListRootId = nil
            model.isPlaybackComplete = false
            model.playListGeneration += 1
            // The old track must not go on playing without a playlist entry if the new load
            // fails. See CODE_AUDIT_23 §5.9.
            model.player.replaceCurrentItem(with: nil)
            // The lock screen must not go on offering the dropped track. See CODE_AUDIT_Audio2 §5.16.
            MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
        }
        // Another replacement can interleave during the loading await below (shared-audio
        // observation, `loadAndPlay`, a game reveal). Items loaded for a playlist that has
        // been replaced since are discarded, not appended. See CODE_AUDIT_18 §3.7.
        let generation = model.playListGeneration

        let requests = models.compactMap { item -> AudioTrackLoader.Request? in
            guard let fileUrl = item.fileUrl else { return nil }
            return AudioTrackLoader.Request(
                id: item.id,
                title: item.name,
                subtitle: PlaylistItem.subtitle(fromDescription: item.description),
                fileUrl: fileUrl
            )
        }
        let playItems = await trackLoader.load(requests)
        guard model.playListGeneration == generation else {
            for item in playItems {
                try? FileManager.default.removeItem(at: item.url)
            }
            return false
        }
        // Nothing loaded (offline iCloud file, failed copy): there is no track to select or play.
        guard !playItems.isEmpty || requests.isEmpty else { return false }
        // Two loads can bring the same track (a background load of the playlist and a track that
        // arrived meanwhile): the track that is in the playlist already stays, the copy goes.
        let present = Set(model.playList.map(\.id))
        let freshItems = playItems.filter { !present.contains($0.id) }
        for item in playItems where present.contains(item.id) {
            try? FileManager.default.removeItem(at: item.url)
        }
        // Single mutation: one observation change instead of one per item.
        model.playList.append(contentsOf: freshItems)
        return true
    }

    @MainActor func loadAndPlay(id: UUID) {
        // If item is already in playlist, just play it
        guard !model.playList.contains(where: { $0.id == id }) else {
            togglePlay(id: id)
            return
        }
        // Item not in playlist, load it first
        let models = [itemController.itemOrEmpty(for: id)]
        // Cancel-then-replace, and stop when the load was discarded: tapping track A and then
        // B, with A's load finishing last, used to select A, which is not in the playlist. That
        // cleared the current item while B was audible and published A as the shared track.
        // See CODE_AUDIT_21 §3.4.
        model.loadAndPlayTask?.cancel()
        let generation = model.playbackGeneration
        model.loadAndPlayTask = Task {
            guard await add(audio: models, replace: true), !Task.isCancelled else { return }
            // After loading, set it as current and play, unless a pause came in meanwhile.
            model.set(currentId: id)
            await preparePlay(id: id, triggerPlay: model.playbackGeneration == generation)
        }
    }

    @MainActor func removeAudio(id: UUID) {
        if model.currentId == id && model.isPlaying {
            pause()
        }
        guard let index = model.playList.firstIndex(where: { $0.id == id }) else { return }
        // Free the item's temp copy along with its playlist entry — every load makes a file of
        // its own (see `AudioTrackLoader`), so nothing else will reclaim it once it's gone from
        // the list. See CODE_AUDIT §7.1.
        try? FileManager.default.removeItem(at: model.playList[index].url)
        model.playList.remove(at: index)
        // The removed item may have been the current-but-paused track: `currentItem`
        // is a stored reference, not derived from `playList`, so leaving it pointing
        // at a row no longer in the list would permanently break `currentIndex`
        // (and therefore hasNext/hasPrev). Clear it explicitly instead. See CODE_AUDIT_Audio §5.3.
        if model.currentId == id {
            model.currentItem = nil
            // The player and the lock screen still held the removed track.
            model.player.replaceCurrentItem(with: nil)
            MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: model.playList.count)
        }
    }

}

extension AudioController {
    /// Loads the track `id` into the player and, with `triggerPlay`, starts it. `startAt` seeks
    /// before the start, so a positioned start never plays from the beginning first. A pause that
    /// comes in while the track loads (or the session activates) is not overridden: the track
    /// is prepared and stays paused.
    @MainActor
    func preparePlay(
        id: UUID,
        triggerPlay: Bool = true,
        startAt: TimeInterval? = nil,
        coordinationId: UUID? = nil
    ) async {
        initAudioSessionEngine()
        let generation = model.playbackGeneration
        // A prior playlist-completion (see advanceAfterTrackEnd) must not stick past the
        // track it applied to — otherwise every later toggle() treats playback as
        // "finished" and restarts from 0:00 instead of resuming. See CODE_AUDIT_Audio §5.2.
        model.isPlaybackComplete = false
        if model.currentId != id {
            model.set(currentId: id)
        }
        // A track that did not load is no current item: do not resume whatever the player held
        // before. See CODE_AUDIT_23 §5.9.
        guard model.currentItem != nil else {
            model.player.replaceCurrentItem(with: nil)
            MediaPlayerCoordinator.handleItemChange(item: nil, index: 0, count: 0)
            return
        }
        // Must set coordinator ID before replacing the item — the AVPlayerPlaybackCoordinator
        // calls identifierFor(_:) during replaceCurrentItem, and needs the UUID already set.
        // Without this order the coordinator gets a random UUID on first play (works second time
        // only because sharedAudioId is already populated from the previous call).
        model.coordinator?.coordinatePlayback(of: coordinationId ?? id)
        replaceCurrentItem()
        if let rootId = model.playListRootId, let trackId = model.currentId {
            model.trackStartHandler?(rootId, trackId)
        }
        if let startAt {
            await seekAndWait(to: startAt)
        }
        guard triggerPlay, model.playbackGeneration == generation else { return }
        play()
    }

    @MainActor
    func replaceCurrentItem() {
        guard let currentItem = model.currentItem, let index = model.currentIndex else { return }

        let playerItem = AVPlayerItem(url: currentItem.url)
        model.player.replaceCurrentItem(with: playerItem)
        MediaPlayerCoordinator.handleItemChange(item: currentItem, index: index, count: model.playList.count)
        Logger.audioController.debug("🎧 \(currentItem.title, privacy: .private) -> \(currentItem.subtitle, privacy: .private)  enqueued for playback.")
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
}

extension AudioController {
    /// The current track ended (`complete`) or the playlist moves on: advances to the next track,
    /// loops, or stops at the end.
    @MainActor func advanceAfterTrackEnd(complete: Bool) {
        guard let currentIndex = model.currentIndex else { return }
        if currentIndex < model.playList.count - 1 {
            togglePlay(id: model.playList[currentIndex + 1].id)
        } else if model.repeatPlayList, let first = model.playList.first,
                  model.loopReplayHandler != nil || !model.isGameRunning() {
            if let loopReplayHandler = model.loopReplayHandler {
                // In a game the loop is a new play for everyone: the game master sends the play
                // command. A player's device does not loop on its own (its Repeat toggle is
                // ignored while a game runs), it plays again when that command arrives.
                loopReplayHandler(AudioPlayRequest(id: model.playListRootId ?? first.id, shouldPlay: true, coordinationId: UUID()).command)
            } else if model.playList.count > 1 {
                togglePlay(id: first.id)
            } else {
                // A one-track playlist: `togglePlay` only switches to another track, so the
                // track is prepared again, which plays it from the start. Repeat used to do
                // nothing for a single looping track. See CODE_AUDIT_21 §5.20.
                Task {
                    await preparePlay(id: first.id)
                }
            }
        } else {
            model.isPlaybackComplete = complete
            if complete {
                model.wantsPlayback = false
                // Nothing is left to play: other apps may have the audio session back.
                model.audioSession?.deactivate()
            }
        }
    }
}

// MARK: - AudioPlayerSessionDelegate

extension AudioController: AudioPlayerSessionDelegate {
    /// A pause is a transport action: with other SharePlay participants it would stop the music
    /// for the whole group because one device lost its headset. There the output is muted on this
    /// device only; the volume bar shows it and an unmute restores the level.
    /// See CODE_AUDIT_28 §3.2.
    @MainActor func routeChanged() {
        guard model.isPlaying else { return }
        if model.isPlaybackShared {
            model.volume = 0
        } else {
            pause()
        }
    }

    /// Whether audio was meant to be playing: the app's own intent, not the observed player
    /// state, which a task updates and which the system's pause may or may not have reached
    /// yet. The player is paused without giving the intent up. See CODE_AUDIT_21 §5.28.
    @MainActor func beginInterruption() -> Bool {
        // A play that is on its way (activating the session) must not start inside the interruption.
        model.playbackGeneration += 1
        guard model.wantsPlayback else { return false }
        // The system already stopped the output; an explicit pause would also be sent to the
        // group, whose playback coordinator suspends and rejoins this device by itself.
        if !model.isPlaybackShared {
            model.player.pause()
        }
        return true
    }

    /// `play()`, not a toggle: a player that had already resumed was paused by the toggle.
    /// Without `wasPlaying` the interruption ended without a request to resume: the intent to
    /// play is given up, so a seek or a command that reads it does not start the audio on its
    /// own. See CODE_AUDIT_Audio2 §5.12.
    @MainActor func endInterruption(wasPlaying: Bool) {
        // With other participants the group decides: a `play()` here would restart music the game
        // master paused during the interruption, for everyone.
        guard !model.isPlaybackShared else { return }
        if wasPlaying {
            play()
        } else if !model.isPlaying {
            model.wantsPlayback = false
        }
    }

    /// After the media server was reset its objects are dead, the player among them: it is
    /// replaced with its observers and loaded with the current track again. The old player
    /// was kept, so nothing played until the app was restarted. See CODE_AUDIT_21 §5.28.
    @MainActor
    func resetMediaService() {
        removeTimeObserver()
        model.removeObservationTasks()
        model.seekTask?.cancel()
        model.playbackGeneration += 1
        model.player = AVPlayer()
        model.isPlaying = false
        model.wantsPlayback = false
        model.isInitialized = false
        initAudioSessionEngine()
        // The new coordinator must know the shared audio id before the item is replaced, as in
        // `preparePlay`; otherwise it asks for it and gets a random one. See CODE_AUDIT_23 §5.22.
        if let currentId = model.currentId {
            model.coordinator?.coordinatePlayback(of: currentId)
        }
        replaceCurrentItem()
        // A running SharePlay session still coordinates the dead player. See CODE_AUDIT_Audio2 §5.9.
        if let coordinator = model.coordinator {
            model.coordinatorDidChange?(coordinator)
        }
    }
}

// MARK: - RemoteCommandHandler

extension AudioController: RemoteCommandHandler {
    func performRemoteCommand(_ command: RemoteCommand) {
        Task { @MainActor in
            // In a game the command goes through the game, so every player follows.
            if model.remoteCommandRouter?(command) == true { return }
            switch command {
            case .togglePlayPause:
                if model.isPlaying { pause() } else { toggle() }
            case .pause:
                pause()
            case .play:
                play()
            case .nextTrack:
                skip(offsetBy: 1)
            case .previousTrack:
                skip(offsetBy: -1)
            case .changePlaybackPosition(let offset):
                seek(to: offset)
            }
        }
    }
}

extension Logger {
    static let audioController = Logger(subsystem: subsystem, category: "AudioController")
}
