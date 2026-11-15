// @copyright André Trettin

#if canImport(Testing)
#if !os(tvOS)
import AVFoundation
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// The playback intents (Siri, Shortcuts) while a game runs and while none does: in a game they
/// go through the game like the player's buttons, so every player follows.
@Suite("Audio intents in a game")
@MainActor
struct AudioIntentGameTests {
    private static func item(_ title: String) -> PlaylistItem {
        PlaylistItem(
            id: UUID(),
            url: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"),
            title: title,
            subtitle: "MasterRPG",
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

    /// Runs `body` as if a game ran on `root`, with `sent` collecting what the intents send to it.
    private static func inGame(
        _ root: AudioRootModel,
        _ sent: AudioPlaybackActionsTests.Sent,
        _ body: () async throws -> Void
    ) async rethrows {
        root.runningGameActions = { sent.actions }
        try await body()
    }

    // MARK: Audio sharing off (CODE_AUDIT_26 §5.29)

    @Test("With audio sharing off a start by intent and a removal send nothing to the game")
    func gateFoldsIntoStartAndRemove() async throws {
        let previous = IntentGameContext.canControlGameAudio
        defer { IntentGameContext.canControlGameAudio = previous }
        IntentGameContext.canControlGameAudio = { false }
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        // The game would drop these from a player that may not control the audio.
        try? await root.startPlayback(id: UUID(), isGameRunning: true, networkActions: sent.actions)
        root.remove(id: tracks[1].id, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.requests.isEmpty)
    }

    @Test("With audio control allowed both still go through the game")
    func gateOpenKeepsSendingToTheGame() async throws {
        let previous = IntentGameContext.canControlGameAudio
        defer { IntentGameContext.canControlGameAudio = previous }
        IntentGameContext.canControlGameAudio = { true }
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        try await root.startPlayback(id: UUID(), isGameRunning: true, networkActions: sent.actions)
        root.remove(id: tracks[1].id, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.requests.count == 2)
    }

    // MARK: In a game

    @Test("Pause by Siri pauses every player")
    func pauseIsSentToTheGame() async throws {
        let (root, _) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) { root.pauseFromIntent() }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(!request.shouldPlay)
        // The game pauses this device with the others.
        #expect(root.audioPlayerModel.wantsPlayback)
    }

    @Test("Resume by Siri resumes the current track for every player")
    func resumeIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        root.audioPlayerModel.isPlaying = false
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) { root.resumeFromIntent() }

        let request = try #require(sent.requests.first)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
    }

    @Test("Next track by Siri plays the next track for every player")
    func nextTrackIsSentToTheGame() async throws {
        let (root, tracks) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()

        await Self.inGame(root, sent) { root.nextTrackFromIntent() }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[2].id)
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    @Test("Play by Siri plays the audio for every player, also when it already plays")
    func playIsSentToTheGame() async throws {
        let (root, _) = Self.playingRoot()
        let sent = AudioPlaybackActionsTests.Sent()
        let audioId = UUID()

        try await Self.inGame(root, sent) { try await root.playFromIntent(id: audioId) }

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.id == audioId)
        #expect(request.shouldPlay)
        #expect(request.trackId == nil)
        // Nothing starts here on its own: the game plays it on every device.
        #expect(root.audioPlayerModel.playList.count == 3)
    }

    // MARK: Without a game

    @Test("Without a game Pause by Siri pauses this device")
    func pauseRunsLocally() {
        let (root, _) = Self.playingRoot()

        root.pauseFromIntent()

        #expect(!root.audioPlayerModel.wantsPlayback)
    }

    @Test("Without a game Next track by Siri skips on this device")
    func nextTrackRunsLocally() {
        let (root, tracks) = Self.playingRoot()

        root.nextTrackFromIntent()

        #expect(root.audioPlayerModel.currentId == tracks[2].id)
    }

    @Test("Without a game Play by Siri loads and plays the audio on this device")
    func playRunsLocally() async throws {
        let root = try await MockRoot.importTestData()
        let audioId = try #require(root.itemController.itemDataModel.items.first)

        try await root.playFromIntent(id: audioId)

        #expect(!root.audioPlayerModel.playList.isEmpty)
        #expect(root.audioPlayerModel.wantsPlayback)
    }
}
#endif
#endif
