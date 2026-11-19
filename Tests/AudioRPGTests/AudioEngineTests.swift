// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// CODE_AUDIT_TestGaps §5.5: `AudioController` owns the `AVPlayer`, its observers and the audio
/// session. These tests drive the real player (a track that cannot load is enough for the state
/// machine) and check what a stuck playback in a game would come from: a play that overrides a
/// pause, a second set of observers, a reset that keeps the dead player, a session that is not
/// given back.
@Suite("Audio engine", .serialized)
@MainActor
struct AudioEngineTests {
    /// A playlist item whose file exists (so the cleanup of its temp copy can be seen).
    private static func item(_ title: String, file: Bool = false) throws -> PlaylistItem {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        if file { try Data([0, 1, 2]).write(to: url) }
        return PlaylistItem(id: UUID(), url: url, title: title, subtitle: "MasterRPG", duration: CMTime(seconds: 30, preferredTimescale: 1))
    }

    private static func exists(_ item: PlaylistItem) -> Bool {
        FileManager.default.fileExists(atPath: item.url.path(percentEncoded: false))
    }

    // MARK: - Play and pause

    @Test("A pause that comes in while the session activates wins over the play on its way")
    func pauseDuringActivationWins() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        sut.prewarm()
        let session = try #require(model.audioSession)
        let generation = model.playbackGeneration

        sut.play()
        #expect(model.wantsPlayback)
        sut.pause()
        await session.waitUntilConfigured()
        _ = await session.activate()

        #expect(!model.wantsPlayback)
        #expect(model.playbackGeneration > generation)
        let stayedPaused = await conditionHolds(for: .milliseconds(150)) { model.player.rate == 0 }
        #expect(stayedPaused, "the play that was waiting for the session must not start the player")
    }

    @Test("A play that nobody paused starts the player once the session is active")
    func playAfterActivationStartsThePlayer() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        sut.prewarm()

        sut.play()

        #expect(await awaitCondition { model.player.rate != 0 })
        #expect(model.wantsPlayback)
        sut.pause()
        #expect(model.player.rate == 0)
    }

    @Test("The session is given back only when nothing plays and nothing is wanted")
    func releaseAudioSessionKeepsItWhilePlaying() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        sut.prewarm()
        let session = try #require(model.audioSession)
        await session.waitUntilConfigured()
        await session.activate()
        #expect(!session.needsActivation)

        model.wantsPlayback = true
        sut.releaseAudioSession()
        #expect(!session.needsActivation, "playback is wanted: the session stays")

        model.wantsPlayback = false
        model.isPlaying = true
        sut.releaseAudioSession()
        #expect(!session.needsActivation, "the player is playing: the session stays")

        model.isPlaying = false
        sut.releaseAudioSession()
        #expect(session.needsActivation, "nothing plays: other apps get the audio back")
    }

    @Test("Choosing another track while one plays pauses first and makes the other current")
    func switchingTrackPausesTheCurrentOne() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First")
        let second = try Self.item("Second")
        model.playList = [first, second]
        model.currentItem = first
        model.isPlaying = true
        model.wantsPlayback = true

        sut.togglePlay(id: second.id)

        #expect(model.currentId == second.id)
        #expect(!model.wantsPlayback)
    }

    // MARK: - Skip and seek

    @Test("Skipping does nothing without a current track or past either end")
    func skipStaysInsideThePlaylist() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First")
        let second = try Self.item("Second")
        model.playList = [first, second]

        sut.skip(offsetBy: 1)
        #expect(model.currentId == nil)

        model.currentItem = second
        sut.skip(offsetBy: 1)
        #expect(model.currentId == second.id)
        sut.skip(offsetBy: 5)
        #expect(model.currentId == second.id)
        sut.skip(offsetBy: -5)
        #expect(model.currentId == second.id)
    }

    @Test("A newer seek replaces the one that is still running")
    func newerSeekCancelsTheOlder() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel

        sut.seek(to: 10)
        let older = try #require(model.seekTask)
        sut.seek(to: 20)
        let newer = try #require(model.seekTask)

        #expect(older.isCancelled)
        #expect(!newer.isCancelled)
        await newer.value
    }

    @Test("A seek position keeps sub-second precision")
    func seekTimeKeepsFractions() {
        let time = AudioController.seekTime(1.5)

        #expect(time.timescale == 600)
        #expect(time.value == 900)
        #expect(time.seconds == 1.5)
    }

    // MARK: - Playlist

    @Test("Replacing the playlist frees the dropped temp copies and forgets the old state")
    func replaceFreesTempFiles() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First", file: true)
        let second = try Self.item("Second", file: true)
        model.playList = [first, second]
        model.currentItem = first
        model.playListRootId = UUID()
        model.isPlaying = true
        model.isPlaybackComplete = true
        let generation = model.playListGeneration

        let added = await sut.add(audio: [], replace: true)

        #expect(added)
        #expect(!Self.exists(first))
        #expect(!Self.exists(second))
        #expect(model.playList.isEmpty)
        #expect(model.currentItem == nil)
        #expect(model.playListRootId == nil)
        #expect(!model.isPlaying)
        #expect(!model.isPlaybackComplete)
        #expect(model.playListGeneration == generation + 1)
        #expect(model.player.currentItem == nil, "the old track must not go on without a playlist entry")
    }

    @Test("Removing the current track frees its file and clears the player")
    func removingTheCurrentTrackClearsThePlayer() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First", file: true)
        let second = try Self.item("Second", file: true)
        model.playList = [first, second]
        await sut.preparePlay(id: first.id, triggerPlay: false)
        #expect(model.player.currentItem != nil)

        sut.removeAudio(id: first.id)

        #expect(model.playList == [second])
        #expect(model.currentItem == nil)
        #expect(model.player.currentItem == nil)
        #expect(!Self.exists(first))
        #expect(Self.exists(second))
        #expect(model.hasNext == false && model.hasPrev == false)
        try? FileManager.default.removeItem(at: second.url)
    }

    @Test("Removing a track that is not current leaves the current one playing")
    func removingAnotherTrackKeepsTheCurrentOne() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First")
        let second = try Self.item("Second")
        model.playList = [first, second]
        await sut.preparePlay(id: first.id, triggerPlay: false)

        sut.removeAudio(id: second.id)
        sut.removeAudio(id: UUID())

        #expect(model.playList == [first])
        #expect(model.currentId == first.id)
        #expect(model.player.currentItem != nil)
    }

    // MARK: - Observers and media-service reset

    @Test("Preparing the engine again does not add a second set of observers")
    func observersAreStartedOnce() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel

        sut.prewarm()
        let tasks = model.observationTasks
        #expect(tasks.count == 3)
        let session = model.audioSession

        sut.prewarm()
        sut.observePlayback()
        await sut.preparePlay(id: UUID(), triggerPlay: false)

        #expect(model.observationTasks.count == 3, "a double observer shows up as a stuck status")
        #expect(model.audioSession === session)
        #expect(tasks.allSatisfy { !$0.isCancelled })
    }

    @Test("After a media-services reset the player, its observers and its track are new")
    func resetMediaServiceReplacesThePlayer() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let track = try Self.item("Track")
        model.playList = [track]
        await sut.preparePlay(id: track.id, triggerPlay: false)
        let oldPlayer = model.player
        let oldTasks = model.observationTasks
        let generation = model.playbackGeneration
        model.wantsPlayback = true
        model.isPlaying = true
        var announced = 0
        model.coordinatorDidChange = { _ in announced += 1 }
        model.volume = 0.6

        sut.resetMediaService()

        #expect(model.player !== oldPlayer, "the dead player is replaced")
        #expect(model.player.currentItem != nil, "the current track is loaded again")
        #expect(model.currentId == track.id)
        #expect(oldTasks.allSatisfy { $0.isCancelled }, "the old observers are ended")
        #expect(model.observationTasks.count == 3)
        #expect(model.observationTasks.allSatisfy { !$0.isCancelled })
        #expect(model.isInitialized)
        #expect(!model.wantsPlayback)
        #expect(!model.isPlaying)
        #expect(model.playbackGeneration > generation, "a play on its way must not start the new player")
        #expect(announced == 1, "a running SharePlay session learns about the new coordinator")
        #expect(model.coordinator != nil)
        #expect(model.coordinator?.sharedAudioId == track.id)
    }

    // MARK: - Remote commands and volume

    @Test("A remote command the game takes is not acted on locally")
    func gameTakesTheRemoteCommand() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = try Self.item("First")
        let second = try Self.item("Second")
        model.playList = [first, second]
        model.currentItem = first
        var received: [RemoteCommand] = []
        model.remoteCommandRouter = { command in
            received.append(command)
            return true
        }

        sut.performRemoteCommand(.nextTrack)

        #expect(await awaitCondition { received.count == 1 })
        #expect(await conditionHolds(for: .milliseconds(100)) { model.currentId == first.id })

        // Without the game the controller acts itself.
        model.remoteCommandRouter = { _ in false }
        sut.performRemoteCommand(.nextTrack)
        #expect(await awaitCondition { model.currentId == second.id })
    }

    @Test("The volume reaches the player, and a mute remembers the last audible level")
    func volumeAndMute() {
        let model = AudioPlayerModel()
        #expect(model.isMuted == false)

        model.volume = 0.8
        #expect(model.player.volume == 0.8)
        #expect(model.previousVolume == 0.8)

        model.volume = 0
        #expect(model.isMuted)
        #expect(model.player.volume == 0)
        #expect(model.previousVolume == 0.8, "unmuting returns to the level before the mute")
    }
}
#endif
