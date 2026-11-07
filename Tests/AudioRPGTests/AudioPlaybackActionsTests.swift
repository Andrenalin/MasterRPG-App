// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

@Suite("Audio playback actions")
@MainActor
struct AudioPlaybackActionsTests {
    /// Collects what a surface sends to the game.
    @MainActor final class Sent {
        var playRequestIds: [UUID] = []
        var requests: [AudioPlayRequest] = []

        var actions: NetworkActions {
            NetworkActions(
                shareId: { _ in },
                send: { _ in },
                game: { [self] data, type, _ in
                    guard type == .playAudio else { return }
                    playRequestIds.append(data.id)
                    if let request = AudioPlayRequest.decodeData(of: data.data) {
                        requests.append(request)
                    }
                }
            )
        }
    }

    private static func item(_ title: String) -> PlaylistItem {
        PlaylistItem(
            id: UUID(),
            url: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"),
            title: title,
            artist: "MasterRPG",
            duration: CMTime(seconds: 30, preferredTimescale: 1)
        )
    }

    @Test("In a game a play is requested from the game instead of started here")
    func playIsRequestedInAGame() {
        let root = AudioRootModel.testRoot()
        let sent = Sent()
        let item = Self.item("Track")
        root.audioPlayerModel.playList = [item]

        root.playOrRequest(id: item.id, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.playRequestIds == [item.id])
        #expect(root.audioPlayerModel.currentId == nil)
    }

    @Test("Outside a game the item becomes current here and nothing is sent")
    func playRunsLocallyOutsideAGame() {
        let root = AudioRootModel.testRoot()
        let sent = Sent()
        let item = Self.item("Track")
        root.audioPlayerModel.playList = [item]

        root.playOrRequest(id: item.id, isGameRunning: false, networkActions: sent.actions)

        #expect(sent.playRequestIds.isEmpty)
        #expect(root.audioPlayerModel.currentId == item.id)
    }

    @Test("The transport button requests the current item in a game")
    func transportRequestsTheCurrentItem() {
        let root = AudioRootModel.testRoot()
        let sent = Sent()
        let item = Self.item("Track")
        root.audioPlayerModel.playList = [item]
        root.audioPlayerModel.currentItem = item

        root.togglePlayback(isGameRunning: true, networkActions: sent.actions)

        #expect(sent.playRequestIds == [item.id])
    }

    @Test("Removing the playing item in a game asks the game to pause it first")
    func removingThePlayingItemPausesTheGameFirst() {
        let root = AudioRootModel.testRoot()
        let sent = Sent()
        let playing = Self.item("Playing")
        let other = Self.item("Other")
        root.audioPlayerModel.playList = [playing, other]
        root.audioPlayerModel.currentItem = playing
        root.audioPlayerModel.isPlaying = true

        root.remove(id: other.id, isGameRunning: true, networkActions: sent.actions)
        #expect(sent.playRequestIds.isEmpty)

        root.remove(id: playing.id, isGameRunning: true, networkActions: sent.actions)
        #expect(sent.playRequestIds == [playing.id])
        #expect(root.audioPlayerModel.playList.isEmpty)
    }

    // MARK: Transport in a game

    /// Three tracks, the second one current and playing.
    private static func playingRoot() -> (root: AudioRootModel, tracks: [PlaylistItem]) {
        let root = AudioRootModel.testRoot()
        let tracks = [item("First"), item("Second"), item("Third")]
        root.audioPlayerModel.playList = tracks
        root.audioPlayerModel.currentItem = tracks[1]
        root.audioPlayerModel.isPlaying = true
        return (root, tracks)
    }

    @Test("In a game pause asks every device to pause the playlist")
    func pauseIsRequestedForEveryone() throws {
        let (root, _) = Self.playingRoot()
        let sent = Sent()
        let playlistItemId = UUID()
        root.audioPlayerModel.playListRootId = playlistItemId

        root.togglePlayback(isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.id == playlistItemId)
        #expect(!request.shouldPlay)
        // The game pauses it, this device does not pause on its own.
        #expect(root.audioPlayerModel.isPlaying)
    }

    @Test("In a game play after a pause asks every device to resume the current track")
    func resumeIsRequestedForEveryone() throws {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()
        root.audioPlayerModel.isPlaying = false

        root.togglePlayback(isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
    }

    @Test("In a game next asks every device to play the next track")
    func nextIsRequestedForEveryone() throws {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()

        root.skip(offsetBy: 1, isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[2].id)
        // The game moves every device, this one included.
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
    }

    @Test("In a game previous asks every device to play the previous track")
    func previousIsRequestedForEveryone() throws {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()

        root.skip(offsetBy: -1, isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[0].id)
    }

    @Test("A skip command names the playlist item the playlist was started from")
    func skipNamesThePlaylistRoot() throws {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()
        let playlistItemId = UUID()
        root.audioPlayerModel.playListRootId = playlistItemId

        root.skip(offsetBy: 1, isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(request.id == playlistItemId)
        #expect(request.trackId == tracks[2].id)
    }

    @Test("Without a playlist item a skip command names the current track")
    func skipFallsBackToTheCurrentTrack() throws {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()

        root.skip(offsetBy: 1, isGameRunning: true, networkActions: sent.actions)

        #expect(try #require(sent.requests.first).id == tracks[1].id)
    }

    @Test("In a game nothing is sent past the first or last track")
    func skipStopsAtThePlaylistEnds() {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()

        root.audioPlayerModel.currentItem = tracks[2]
        root.skip(offsetBy: 1, isGameRunning: true, networkActions: sent.actions)
        root.audioPlayerModel.currentItem = tracks[0]
        root.skip(offsetBy: -1, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.requests.isEmpty)
    }

    @Test("In a game nothing is sent without a current track")
    func transportNeedsACurrentTrack() {
        let root = AudioRootModel.testRoot()
        let sent = Sent()

        root.skip(offsetBy: 1, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.requests.isEmpty)
    }

    @Test("Outside a game next and previous move here and send nothing")
    func skipRunsLocallyOutsideAGame() {
        let (root, tracks) = Self.playingRoot()
        let sent = Sent()

        root.skip(offsetBy: 1, isGameRunning: false, networkActions: sent.actions)
        #expect(root.audioPlayerModel.currentId == tracks[2].id)

        root.skip(offsetBy: -1, isGameRunning: false, networkActions: sent.actions)
        #expect(root.audioPlayerModel.currentId == tracks[1].id)
        #expect(sent.requests.isEmpty)
    }

    // MARK: Seeking in a game

    @Test("In a game seeking while the audio plays asks every device to seek and keep playing")
    func seekWhilePlayingIsRequestedForEveryone() throws {
        let (root, tracks) = Self.playingRoot()
        root.audioPlayerModel.wantsPlayback = true
        let sent = Sent()

        root.seek(to: 42, isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(sent.requests.count == 1)
        #expect(request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
        #expect(request.position == 42)
        // The game seeks this device with the others.
        #expect(root.audioPlayerModel.seekTask == nil)
    }

    @Test("In a game seeking while paused asks every device to seek and stay paused")
    func seekWhilePausedIsRequestedForEveryone() throws {
        let (root, tracks) = Self.playingRoot()
        root.audioPlayerModel.isPlaying = false
        root.audioPlayerModel.wantsPlayback = false
        let sent = Sent()

        root.seek(to: 7, isGameRunning: true, networkActions: sent.actions)

        let request = try #require(sent.requests.first)
        #expect(!request.shouldPlay)
        #expect(request.trackId == tracks[1].id)
        #expect(request.position == 7)
    }

    @Test("A seek command names the playlist item the playlist was started from")
    func seekNamesThePlaylistRoot() throws {
        let (root, _) = Self.playingRoot()
        let sent = Sent()
        let playlistItemId = UUID()
        root.audioPlayerModel.playListRootId = playlistItemId

        root.seek(to: 3, isGameRunning: true, networkActions: sent.actions)

        #expect(try #require(sent.requests.first).id == playlistItemId)
    }

    @Test("In a game nothing is sent for a seek without a current track or to an invalid position")
    func invalidSeekSendsNothing() {
        let (root, _) = Self.playingRoot()
        let sent = Sent()

        root.seek(to: -1, isGameRunning: true, networkActions: sent.actions)
        root.seek(to: .nan, isGameRunning: true, networkActions: sent.actions)
        root.seek(to: .infinity, isGameRunning: true, networkActions: sent.actions)
        let empty = AudioRootModel.testRoot()
        empty.seek(to: 5, isGameRunning: true, networkActions: sent.actions)

        #expect(sent.requests.isEmpty)
    }

    @Test("Outside a game seeking happens here and sends nothing")
    func seekRunsLocallyOutsideAGame() async {
        let (root, _) = Self.playingRoot()
        let sent = Sent()

        root.seek(to: 5, isGameRunning: false, networkActions: sent.actions)

        #expect(await waitUntil { root.audioPlayerModel.seekTask != nil })
        #expect(sent.requests.isEmpty)
    }

    // MARK: The command

    @Test("A command without a track, as an older device sends it, decodes without one")
    func commandWithoutATrackStillDecodes() throws {
        struct LegacyRequest: Codable, MessageMapper {
            let id: UUID
            let shouldPlay: Bool
        }
        let id = UUID()

        let data = LegacyRequest(id: id, shouldPlay: true).encodeData()
        let request = try #require(AudioPlayRequest.decodeData(of: data))

        #expect(request.id == id)
        #expect(request.shouldPlay)
        #expect(request.trackId == nil)
    }

    @Test("A command without a position decodes without one")
    func commandWithoutAPositionDecodesWithoutOne() throws {
        let command = AudioPlayRequest(id: UUID(), shouldPlay: true, trackId: UUID()).command

        let request = try #require(AudioPlayRequest.decodeData(of: command.data))

        #expect(request.position == nil)
    }

    @Test("The master passes on the position of a player's request and drops an invalid one")
    func sanitizedRequestKeepsAValidPosition() throws {
        let root = AudioRootModel.testRoot()
        let playlistItemId = UUID()
        let valid = AudioPlayRequest(id: playlistItemId, shouldPlay: true, trackId: UUID(), position: 30).command
        let negative = AudioPlayRequest(id: playlistItemId, shouldPlay: true, trackId: UUID(), position: -5).command

        let passedOn = try #require(root.audioGameControllable.sanitizedPlayRequest(from: valid))
        let dropped = try #require(root.audioGameControllable.sanitizedPlayRequest(from: negative))

        #expect(AudioPlayRequest.decodeData(of: passedOn.data)?.position == 30)
        #expect(AudioPlayRequest.decodeData(of: dropped.data)?.position == nil)
    }

    @Test("The master passes on the track of a player's request")
    func sanitizedRequestKeepsTheTrack() throws {
        let root = AudioRootModel.testRoot()
        let playlistItemId = UUID()
        let trackId = UUID()
        let command = AudioPlayRequest(id: playlistItemId, shouldPlay: true, trackId: trackId).command

        let passedOn = try #require(root.audioGameControllable.sanitizedPlayRequest(from: command))

        let request = try #require(AudioPlayRequest.decodeData(of: passedOn.data))
        #expect(request.id == playlistItemId)
        #expect(request.trackId == trackId)
    }
}
#endif
