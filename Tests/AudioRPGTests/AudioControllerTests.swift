// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import Foundation
import Testing

@testable import AudioRPG

@Suite("Audio controller tests")
@MainActor
struct AudioControllerTests {

    @Test("Toggle, skip, reset and remove playlist items update player state")
    func playlistControls() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = Self.playlistItem(title: "First")
        let second = Self.playlistItem(title: "Second")
        let third = Self.playlistItem(title: "Third")
        model.playList = [first, second, third]
        model.currentItem = second

        sut.toggle()
        #expect(model.showPlayerToolBar)

        sut.skipToCurrentItem(offsetBy: 1)
        #expect(model.currentId == third.id)

        model.currentItem = second
        sut.skipToCurrentItem(offsetBy: -1)
        #expect(model.currentId == first.id)

        sut.skipToCurrentItem(offsetBy: -1)
        #expect(model.currentId == first.id)

        model.currentItem = first
        model.isPlaying = true
        sut.removeAudio(id: first.id)
        #expect(!model.playList.contains(first))

        model.isPlaybackComplete = true
        await sut.add(audio: [AudioModel(id: UUID(), name: "No File")], replace: true)
        #expect(model.playList.isEmpty)
        #expect(model.isPlaybackComplete == false)
    }

    @Test("Prepare, replace and load existing playlist item")
    func prepareReplaceAndLoadExistingItem() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = Self.playlistItem(title: "First")
        let second = Self.playlistItem(title: "Second")
        model.playList = [first, second]

        await sut.preparePlay(id: first.id, triggerPlay: false)
        #expect(model.currentId == first.id)
        #expect(model.player.currentItem != nil)

        sut.togglePlay(id: second.id, triggerPlay: false)
        #expect(model.currentId == second.id)

        sut.loadAndPlay(id: first.id)
        #expect(model.currentId == first.id)
    }

    @Test("Interruption and route delegates use play state")
    func interruptionsAndRouteChanges() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel

        model.isPlaying = false
        #expect(sut.beginInterruption() == false)

        model.isPlaying = true
        #expect(sut.beginInterruption())

        model.isPlaying = true
        sut.routeChanged()

        sut.endInterruption(wasPlaying: false)
        sut.endInterruption(wasPlaying: true)
    }

    @Test("Remote commands are dispatched to controller actions")
    func remoteCommands() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let first = Self.playlistItem(title: "First")
        let second = Self.playlistItem(title: "Second")
        model.playList = [first, second]
        model.currentItem = first

        sut.performRemoteCommand(.nextTrack)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.currentId == second.id)

        sut.performRemoteCommand(.previousTrack)
        sut.performRemoteCommand(.changePlaybackPosition(1))
        sut.performRemoteCommand(.pause)
        sut.performRemoteCommand(.play)
        try await Task.sleep(for: .milliseconds(100))
    }
}

private extension AudioControllerTests {
    static func playlistItem(title: String) -> PlaylistItem {
        PlaylistItem(
            id: UUID(),
            url: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a"),
            title: title,
            artist: "MasterRPG",
            duration: CMTime(seconds: 30, preferredTimescale: 1)
        )
    }
}
#endif
