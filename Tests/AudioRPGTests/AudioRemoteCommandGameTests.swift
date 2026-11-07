// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// The remote commands (lock screen, AirPods, headphone buttons) while a game runs and while
/// none does: in a game they go through the game like the player's buttons.
@Suite("Audio remote commands in a game")
@MainActor
struct AudioRemoteCommandGameTests {
    private static func item(_ title: String) -> PlaylistItem {
        PlaylistItem(
            id: UUID(),
            url: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"),
            title: title,
            artist: "MasterRPG",
            duration: CMTime(seconds: 30, preferredTimescale: 1)
        )
    }

    /// Three tracks, the second one current and playing.
    private static func playingRoot() -> (root: AudioRootModel, tracks: [PlaylistItem]) {
        let root = AudioRootModel.testRoot()
        let tracks = [item("First"), item("Second"), item("Third")]
        root.audioPlayerModel.playList = tracks
        root.audioPlayerModel.currentItem = tracks[1]
        root.audioPlayerModel.isPlaying = true
        root.audioPlayerModel.wantsPlayback = true
        return (root, tracks)
    }

    /// Runs `body` as if a game ran on `root`, with `sent` collecting what the commands send to it.
    private static func inGame(
        _ root: AudioRootModel,
        _ sent: AudioPlaybackActionsTests.Sent,
        _ body: () async throws -> Void
    ) async rethrows {
        root.runningGameActions = { sent.actions }
        try await body()
    }

    // MARK: In a game

    @Test("The pause button of the headphones pauses every player")
    func pauseIsSentToTheGame() async throws {
        let (root, _) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            root.audioController.performRemoteCommand(.pause)
            #expect(await waitUntil { !sent.requests.isEmpty })
        }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(!request.shouldPlay)
        // The game pauses this device with the others.
        #expect(root.audioPlayerModel.wantsPlayback)
    }

    @Test("The play button of the headphones resumes the current track for every player")
    func playIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        root.audioPlayerModel.isPlaying = false
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            root.audioController.performRemoteCommand(.play)
            #expect(await waitUntil { !sent.requests.isEmpty })
        }

        let request = try #require(sent.requests.first)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
    }

    @Test("Play while the audio plays sends nothing")
    func playWhilePlayingSendsNothing() async {
        let (root, _) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            #expect(root.routeRemoteCommand(.play))
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(sent.requests.isEmpty)
    }

    @Test("The next track button plays the next track for every player")
    func nextTrackIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            root.audioController.performRemoteCommand(.nextTrack)
            #expect(await waitUntil { !sent.requests.isEmpty })
        }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[2].id)
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    @Test("The previous track button plays the previous track for every player")
    func previousTrackIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            root.audioController.performRemoteCommand(.previousTrack)
            #expect(await waitUntil { !sent.requests.isEmpty })
        }

        let request = try #require(sent.requests.first)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[0].id)
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    @Test("Scrubbing on the lock screen seeks every player")
    func seekingIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) {
            root.audioController.performRemoteCommand(.changePlaybackPosition(12))
            #expect(await waitUntil { !sent.requests.isEmpty })
        }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
        #expect(request.position == 12)
        // The game moves this device with the others.
        #expect(root.audioPlayerModel.seekTask == nil)
    }

    // MARK: Without a game

    @Test("Without a game the remote commands are not routed")
    func commandsAreNotRoutedWithoutAGame() {
        let (root, _) = Self.playingRoot()

        #expect(!root.routeRemoteCommand(.pause))
        #expect(!root.routeRemoteCommand(.play))
        #expect(!root.routeRemoteCommand(.nextTrack))
        #expect(!root.routeRemoteCommand(.previousTrack))
        #expect(!root.routeRemoteCommand(.changePlaybackPosition(5)))
    }

    @Test("Without a game scrubbing seeks on this device")
    func seekingRunsLocally() async {
        let (root, _) = Self.playingRoot()

        root.audioController.performRemoteCommand(.changePlaybackPosition(5))

        #expect(await waitUntil { root.audioPlayerModel.seekTask != nil })
    }

    @Test("Without a game the next track button skips on this device")
    func nextTrackRunsLocally() async {
        let (root, tracks) = Self.playingRoot()

        root.audioController.performRemoteCommand(.nextTrack)

        #expect(await waitUntil { root.audioPlayerModel.currentId == tracks[2].id })
    }

    @Test("Without a game the pause button pauses this device")
    func pauseRunsLocally() async {
        let (root, _) = Self.playingRoot()

        root.audioController.performRemoteCommand(.pause)

        #expect(await waitUntil { !root.audioPlayerModel.wantsPlayback })
    }
}
#endif
