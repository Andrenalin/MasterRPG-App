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

        var actions: NetworkActions {
            NetworkActions(
                shareId: { _ in },
                send: { _ in },
                game: { [self] data, type, _ in
                    if type == .playAudio { playRequestIds.append(data.id) }
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
}
#endif
