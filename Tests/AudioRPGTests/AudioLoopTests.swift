// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// What the playlist loop does when a track ends, without and with a game.
@Suite("Audio loop")
@MainActor
struct AudioLoopTests {
    /// Collects the play commands the loop hands to the game.
    @MainActor final class Replays {
        var commands: [NetworkCodableDataType] = []

        var requests: [AudioPlayRequest] {
            commands.compactMap { AudioPlayRequest.decodeData(of: $0.data) }
        }
    }

    private static func item(_ title: String) -> PlaylistItem {
        PlaylistItem(
            id: UUID(),
            url: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"),
            title: title,
            subtitle: "MasterRPG",
            duration: CMTime(seconds: 30, preferredTimescale: 1)
        )
    }

    /// A root whose playlist ended: the last of `count` tracks is current.
    private static func rootAtLastTrack(count: Int) -> (root: AudioRootModel, tracks: [PlaylistItem]) {
        let root = AudioRootModel.testRoot()
        let tracks = (1...count).map { item("Track \($0)") }
        root.audioPlayerModel.playList = tracks
        root.audioPlayerModel.currentItem = tracks.last
        return (root, tracks)
    }

    // MARK: Without a game

    @Test("The loop is off by default")
    func loopIsOffByDefault() {
        #expect(AudioRootModel.testRoot().audioPlayerModel.repeatPlayList == false)
    }

    @Test("Without a loop the end of the last track completes the playlist")
    func endOfPlaylistCompletes() {
        let (root, _) = Self.rootAtLastTrack(count: 2)
        let model = root.audioPlayerModel
        model.wantsPlayback = true

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(model.isPlaybackComplete)
        #expect(!model.wantsPlayback)
    }

    @Test("With a loop the end of the last track starts the first one again")
    func loopRestartsAtTheFirstTrack() {
        let (root, tracks) = Self.rootAtLastTrack(count: 3)
        root.audioPlayerModel.repeatPlayList = true

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(root.audioPlayerModel.currentId == tracks.first?.id)
        #expect(!root.audioPlayerModel.isPlaybackComplete)
    }

    @Test("A track in the middle of the playlist advances, loop or not")
    func middleTrackAdvances() {
        let root = AudioRootModel.testRoot()
        let tracks = [Self.item("A"), Self.item("B"), Self.item("C")]
        root.audioPlayerModel.playList = tracks
        root.audioPlayerModel.currentItem = tracks[0]
        root.audioPlayerModel.repeatPlayList = true

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    // MARK: In a game

    @Test("In a game the loop hands a play command for the first track to the game")
    func loopAsksTheGameToReplay() throws {
        let (root, tracks) = Self.rootAtLastTrack(count: 3)
        let replays = Replays()
        root.audioPlayerModel.repeatPlayList = true
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }

        root.audioController.advanceAfterTrackEnd(complete: true)

        let command = try #require(replays.commands.first)
        let request = try #require(replays.requests.first)
        #expect(replays.commands.count == 1)
        #expect(command.type == .audio)
        #expect(command.id == request.id)
        #expect(request.id == tracks.first?.id)
        #expect(request.shouldPlay)
        // The game restarts it on every device, so this device does not restart it on its own.
        #expect(root.audioPlayerModel.currentId == tracks.last?.id)
    }

    @Test("In a game the loop replays the item the playlist was started from")
    func loopReplaysThePlaylistRoot() throws {
        let (root, _) = Self.rootAtLastTrack(count: 3)
        let replays = Replays()
        let playlistItemId = UUID()
        root.audioPlayerModel.repeatPlayList = true
        root.audioPlayerModel.playListRootId = playlistItemId
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }

        root.audioController.advanceAfterTrackEnd(complete: true)

        let request = try #require(replays.requests.first)
        #expect(request.id == playlistItemId)
        #expect(request.shouldPlay)
    }

    @Test("In a game a one-track loop is replayed through the game too")
    func singleTrackLoopAsksTheGame() throws {
        let (root, tracks) = Self.rootAtLastTrack(count: 1)
        let replays = Replays()
        root.audioPlayerModel.repeatPlayList = true
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(replays.requests.map(\.id) == [tracks[0].id])
    }

    @Test("In a game nothing is replayed while the loop is off")
    func noReplayWithoutLoop() {
        let (root, _) = Self.rootAtLastTrack(count: 2)
        let replays = Replays()
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(replays.commands.isEmpty)
        #expect(root.audioPlayerModel.isPlaybackComplete)
    }

    @Test("In a game nothing is replayed before the last track ended")
    func noReplayBeforeTheEnd() {
        let root = AudioRootModel.testRoot()
        let tracks = [Self.item("A"), Self.item("B")]
        let replays = Replays()
        root.audioPlayerModel.playList = tracks
        root.audioPlayerModel.currentItem = tracks[0]
        root.audioPlayerModel.repeatPlayList = true
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(replays.commands.isEmpty)
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    @Test("Removing the handler lets the loop restart locally again")
    func removedHandlerRestoresTheLocalLoop() {
        let (root, tracks) = Self.rootAtLastTrack(count: 2)
        let replays = Replays()
        root.audioPlayerModel.repeatPlayList = true
        root.audioGameControllable.setLoopReplayHandler { replays.commands.append($0) }
        root.audioGameControllable.setLoopReplayHandler(nil)

        root.audioController.advanceAfterTrackEnd(complete: true)

        #expect(replays.commands.isEmpty)
        #expect(root.audioPlayerModel.currentId == tracks.first?.id)
    }

    @Test("Replacing the playlist forgets the item it was started from")
    func replacingThePlaylistClearsTheRoot() async {
        let root = AudioRootModel.testRoot()
        root.audioPlayerModel.playListRootId = UUID()

        await root.audioController.add(audio: [], replace: true)

        #expect(root.audioPlayerModel.playListRootId == nil)
    }
}
#endif
