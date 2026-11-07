// @copyright André Trettin

#if canImport(Testing)
import AVFoundation
import CoreRPG
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

        sut.skip(offsetBy: 1)
        #expect(model.currentId == third.id)

        model.currentItem = second
        sut.skip(offsetBy: -1)
        #expect(model.currentId == first.id)

        sut.skip(offsetBy: -1)
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

        await sut.preparePlay(id: second.id, triggerPlay: false)
        #expect(model.currentId == second.id)

        sut.loadAndPlay(id: first.id)
        #expect(model.currentId == first.id)
    }

    // CODE_AUDIT_21 §3.4: a load a newer replacement superseded reported nothing, so its caller
    // went on to select a track that is not in the playlist.
    @Test("A playlist load superseded by a newer replacement reports that it was discarded")
    func supersededLoadReportsDiscard() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel
        let current = Self.playlistItem(title: "Current")
        model.playList = [current]
        model.currentItem = current
        let stale = AudioModel(
            id: UUID(),
            name: "Stale",
            fileUrl: FileUrl(importedData: Data([0, 1, 2, 3]), fileId: UUID(), filename: "stale.m4a", module: "audios")
        )

        let generation = model.playListGeneration
        // Suspends in its off-main load after it replaced the playlist.
        let staleLoad = Task { await sut.add(audio: [stale], replace: true) }
        while model.playListGeneration == generation {
            await Task.yield()
        }
        let newerLoad = await sut.add(audio: [], replace: true)

        #expect(newerLoad)
        #expect(await staleLoad.value == false)
        #expect(model.playList.isEmpty)
    }

    @Test("Interruption and route delegates use play state")
    func interruptionsAndRouteChanges() async throws {
        let root = AudioRootModel.testRoot()
        let sut = root.audioController
        let model = root.audioPlayerModel

        // CODE_AUDIT_21 §5.28: "was playing" is the app's own intent, not the observed player
        // state, which an observer task updates and the system's pause may already have changed.
        model.isPlaying = true
        #expect(sut.beginInterruption() == false)

        sut.play()
        model.isPlaying = false
        #expect(sut.beginInterruption())
        // The interruption does not give the intent up, so a second report still resumes.
        #expect(model.wantsPlayback)

        sut.pause()
        #expect(sut.beginInterruption() == false)

        // Unplugged headphones pause for good.
        sut.play()
        model.isPlaying = true
        sut.routeChanged()
        #expect(!model.wantsPlayback)

        sut.endInterruption(wasPlaying: false)
        #expect(!model.wantsPlayback)
        sut.endInterruption(wasPlaying: true)
        #expect(model.wantsPlayback)
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
        #expect(await waitUntil { model.currentId == second.id })

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
            subtitle: "MasterRPG",
            duration: CMTime(seconds: 30, preferredTimescale: 1)
        )
    }
}
#endif
