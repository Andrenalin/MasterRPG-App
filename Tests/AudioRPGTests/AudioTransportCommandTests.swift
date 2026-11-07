// @copyright André Trettin

#if canImport(Testing)
import CoreMedia
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// What a device does with the play, pause, resume, next and previous commands of a game.
@Suite("Audio transport commands")
@MainActor
struct AudioTransportCommandTests {
    /// The imported test data: a playlist item of two tracks, played from its own file first.
    private struct Fixture {
        let root: AudioRootModel
        let playlistItemId: UUID
        let trackIds: [UUID]
    }

    private static func fixture() async throws -> Fixture {
        let root = try await MockRoot.importTestData()
        let playlistItemId = try #require(
            root.itemController.itemDataModel.items.first { !root.gameController.gameItem(for: $0).entries.isEmpty }
        )
        let trackIds = root.gameController.fetchPlaylist(id: playlistItemId).map(\.id)
        try #require(trackIds.count == 2)
        return Fixture(root: root, playlistItemId: playlistItemId, trackIds: trackIds)
    }

    private static func start(_ fixture: Fixture) async throws {
        try await fixture.root.gameController.play(AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true))
    }

    @Test("A play command loads the playlist and starts its first track")
    func playStartsTheFirstTrack() async throws {
        let fixture = try await Self.fixture()

        try await Self.start(fixture)

        let model = fixture.root.audioPlayerModel
        #expect(model.playList.map(\.id) == fixture.trackIds)
        #expect(model.currentId == fixture.trackIds[0])
        #expect(model.playListRootId == fixture.playlistItemId)
        #expect(model.wantsPlayback)
    }

    @Test("A next command plays the second track without loading the playlist again")
    func nextPlaysTheNextTrack() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        let generation = model.playListGeneration

        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1])
        )

        #expect(model.currentId == fixture.trackIds[1])
        #expect(model.playListGeneration == generation)
        #expect(model.wantsPlayback)
    }

    @Test("A previous command plays the first track again")
    func previousPlaysThePreviousTrack() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1])
        )
        let generation = model.playListGeneration

        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0])
        )

        #expect(model.currentId == fixture.trackIds[0])
        #expect(model.playListGeneration == generation)
    }

    @Test("A pause command pauses the playlist")
    func pauseCommandPauses() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        #expect(model.wantsPlayback)

        try await fixture.root.gameController.play(AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: false))

        #expect(!model.wantsPlayback)
        // Pausing keeps the playlist and the track.
        #expect(model.currentId == fixture.trackIds[0])
        #expect(model.playList.count == 2)
    }

    @Test("A command for the current track after a pause resumes it instead of starting it again")
    func resumeContinuesTheCurrentTrack() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        try await fixture.root.gameController.play(AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: false))
        let generation = model.playListGeneration

        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0])
        )

        #expect(model.wantsPlayback)
        #expect(model.currentId == fixture.trackIds[0])
        #expect(model.playListGeneration == generation)
    }

    @Test("A device that has not loaded the playlist loads it and plays the named track")
    func commandLoadsThePlaylistOfALateDevice() async throws {
        let fixture = try await Self.fixture()

        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1])
        )

        let model = fixture.root.audioPlayerModel
        #expect(model.playList.map(\.id) == fixture.trackIds)
        #expect(model.currentId == fixture.trackIds[1])
        #expect(model.playListRootId == fixture.playlistItemId)
    }

    @Test("A command for a track that is not in the playlist starts the first track")
    func unknownTrackStartsTheFirstTrack() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)

        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: UUID())
        )

        #expect(fixture.root.audioPlayerModel.currentId == fixture.trackIds[0])
    }

    @Test("A command decoded from the network is applied the same way")
    func networkCommandIsApplied() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let command = AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1]).command

        try await fixture.root.audioGameControllable.play(with: command)

        #expect(fixture.root.audioPlayerModel.currentId == fixture.trackIds[1])
    }

    // MARK: Seeking

    /// Where the tests seek to: the middle of the first track.
    private static func middle(of fixture: Fixture) throws -> TimeInterval {
        let duration = try #require(fixture.root.audioPlayerModel.playList.first?.duration.seconds)
        try #require(duration > 1)
        return (duration / 2).rounded()
    }

    private static func isNear(_ fixture: Fixture, _ position: TimeInterval) -> Bool {
        abs(fixture.root.audioPlayerModel.currentTime - position) < 1
    }

    @Test("A seek command moves the playing track and keeps it playing")
    func seekWhilePlaying() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        let position = try Self.middle(of: fixture)
        let generation = model.playListGeneration

        try await fixture.root.gameController.play(AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0], position: position
        ))

        #expect(await waitUntil { Self.isNear(fixture, position) })
        #expect(model.wantsPlayback)
        #expect(model.currentId == fixture.trackIds[0])
        #expect(model.playListGeneration == generation)
    }

    @Test("A seek command while paused moves the track and keeps it paused")
    func seekWhilePaused() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        let position = try Self.middle(of: fixture)

        try await fixture.root.gameController.play(AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: false, trackId: fixture.trackIds[0], position: position
        ))

        #expect(await waitUntil { Self.isNear(fixture, position) })
        #expect(!model.wantsPlayback)
        #expect(model.currentId == fixture.trackIds[0])
    }

    @Test("A seek command brings a device that is on another track to the master's track")
    func seekMovesADeviceOnAnotherTrack() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        // This device already moved on to the second track.
        try await fixture.root.gameController.play(
            AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1])
        )
        #expect(model.currentId == fixture.trackIds[1])
        let position = try Self.middle(of: fixture)

        try await fixture.root.gameController.play(AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0], position: position
        ))

        #expect(model.currentId == fixture.trackIds[0])
        #expect(await waitUntil { Self.isNear(fixture, position) })
    }

    @Test("A seek command loads the playlist on a device that has not loaded it")
    func seekLoadsThePlaylistOfALateDevice() async throws {
        let fixture = try await Self.fixture()
        let position: TimeInterval = 1

        try await fixture.root.gameController.play(AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0], position: position
        ))

        let model = fixture.root.audioPlayerModel
        #expect(model.playList.map(\.id) == fixture.trackIds)
        #expect(model.wantsPlayback)
        #expect(await waitUntil { Self.isNear(fixture, position) })
    }

    @Test("A seek command with an invalid position leaves the position alone")
    func invalidPositionIsIgnored() async throws {
        let fixture = try await Self.fixture()
        try await Self.start(fixture)
        let model = fixture.root.audioPlayerModel
        let seeksBefore = model.seekTask == nil

        try await fixture.root.gameController.play(AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0], position: -10
        ))

        #expect(model.wantsPlayback)
        #expect(model.currentId == fixture.trackIds[0])
        #expect(seeksBefore == (model.seekTask == nil))
    }

    @Test("A SharePlay receiver leaves the position to the coordinator")
    func sharePlayReceiverIgnoresThePosition() async throws {
        let fixture = try await Self.fixture()
        await fixture.root.audioGameControllable.loadPlaylist(id: fixture.playlistItemId)
        let model = fixture.root.audioPlayerModel
        let position = try Self.middle(of: fixture)

        let command = AudioPlayRequest(
            id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[0], position: position
        ).command
        await fixture.root.audioGameControllable.loadPlaylist(with: command)

        #expect(model.seekTask == nil)
        #expect(!model.wantsPlayback)
    }

    // MARK: SharePlay receivers

    @Test("A SharePlay receiver only prepares the track a next command names")
    func sharePlayReceiverPreparesTheNamedTrack() async throws {
        let fixture = try await Self.fixture()
        await fixture.root.audioGameControllable.loadPlaylist(id: fixture.playlistItemId)
        let model = fixture.root.audioPlayerModel
        #expect(model.currentId == fixture.trackIds[0])

        let command = AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true, trackId: fixture.trackIds[1]).command
        await fixture.root.audioGameControllable.loadPlaylist(with: command)

        #expect(model.currentId == fixture.trackIds[1])
        // The coordinator starts it with the game master's playback.
        #expect(!model.wantsPlayback)
    }

    @Test("A SharePlay receiver leaves the playlist alone on a pause command")
    func sharePlayReceiverIgnoresPause() async throws {
        let fixture = try await Self.fixture()
        await fixture.root.audioGameControllable.loadPlaylist(id: fixture.playlistItemId)
        let model = fixture.root.audioPlayerModel
        let generation = model.playListGeneration

        let command = AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: false).command
        await fixture.root.audioGameControllable.loadPlaylist(with: command)

        #expect(model.playListGeneration == generation)
        #expect(model.currentId == fixture.trackIds[0])
    }

    @Test("A SharePlay receiver loads the playlist for a play command that names no track")
    func sharePlayReceiverLoadsForAPlainPlay() async throws {
        let fixture = try await Self.fixture()

        let command = AudioPlayRequest(id: fixture.playlistItemId, shouldPlay: true).command
        await fixture.root.audioGameControllable.loadPlaylist(with: command)

        let model = fixture.root.audioPlayerModel
        #expect(model.playList.map(\.id) == fixture.trackIds)
        #expect(model.currentId == fixture.trackIds[0])
        #expect(!model.wantsPlayback)
    }
}
#endif
