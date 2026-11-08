// @copyright André Trettin

#if canImport(Testing)
import CoreMedia
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import GameRPG

/// A playlist with many tracks cannot travel at once: SharePlay uploads one file per Journal slot.
/// A game master sends the playlist item and its first track before the play starts, every other
/// track alone and ahead of its play, and nothing to a player that already has it. These tests
/// follow the bytes over a real master and real players on an in-memory network.
@Suite("Audio playlist game flow", .serialized)
@MainActor
struct AudioPlaylistGameFlowTests {
    private struct Playlist {
        let rootId: UUID
        let trackIds: [UUID]
    }

    private struct Setup {
        let env: LinkedGameEnvironment
        let player: LinkedGameEnvironment.Player
        let playlist: Playlist
    }

    /// How long a wait for the network may take. A wait returns as soon as it holds, so this only
    /// matters on a loaded CI machine, where the game master's own track start (which triggers the
    /// look-ahead) can take seconds. With the default of two seconds a test went on without the
    /// look-ahead and then saw its package a second time.
    private static let patience: Duration = .seconds(30)

    // MARK: Fixture

    /// A container playlist with `trackCount` file-backed tracks in the game master's library.
    private static func insertPlaylist(into root: AudioRootModel, trackCount: Int) async throws -> Playlist {
        var found: FileUrl?
        for id in root.itemController.itemDataModel.items {
            if let fileUrl = root.itemController.itemSync(for: id)?.fileUrl {
                found = fileUrl
                break
            }
        }
        let source = try #require(found)
        let controller = try #require(root.itemController.fileUrlDataController)
        let audio = try #require(await controller.loadData(for: source))

        var trackIds: [UUID] = []
        for number in 1...trackCount {
            let id = UUID()
            let url = URL.temporaryDirectory.appending(path: "playlist-flow-\(id.uuidString).m4a")
            try audio.write(to: url)
            let fileUrl = FileUrl(fileId: id, url: url, location: .local, module: NetworkModules.audio.token, relativeUrl: nil)
            root.itemController.replace(model: AudioModel(id: id, name: "Track \(number)", fileUrl: fileUrl), isInsert: true)
            trackIds.append(id)
        }
        let rootId = UUID()
        root.itemController.replace(
            model: AudioModel(
                id: rootId,
                name: "Long playlist",
                entries: trackIds.map { AudioEntryModel(id: UUID(), audioId: $0) }
            ),
            isInsert: true
        )
        return Playlist(rootId: rootId, trackIds: trackIds)
    }

    /// A game master with a four-track playlist, and one player that has no audio.
    private static func setup(trackCount: Int = 4) async throws -> Setup {
        let env = try await LinkedGameEnvironment.create()
        try await env.importData(named: ResourcesDebug.audioTestData, into: env.masterRoot)
        let playlist = try await insertPlaylist(into: env.masterRoot.audioRoot, trackCount: trackCount)
        env.masterRoot.adventureRoot.startGame()
        env.master.installAudioPrefetch()
        let player = try await env.addPlayer(named: "Player - 1")
        player.root.adventureRoot.startGame()
        await join(player, in: env)
        env.clearHistory()
        return Setup(env: env, player: player, playlist: playlist)
    }

    /// The connect handshake, and then the wait until the game master took the player in: the
    /// player's audio list is its first message, so it reaches the master after `ready`. A play
    /// sent before that finds a player the master does not know (nothing is sent to them), and a
    /// list that arrives while the delivery runs sends the same package a second time.
    private static func join(_ player: LinkedGameEnvironment.Player, in env: LinkedGameEnvironment) async {
        let listsBefore = audioListCount(to: player, in: env)
        await env.ready(player)
        let isKnown = await waitUntil(timeout: Self.patience) {
            audioListCount(to: player, in: env) > listsBefore
                && env.masterRoot.audioRoot.gameControllable.gameModel.currentPlayers.contains(player.id)
        }
        #expect(isKnown, "The game master never took the player in")
    }

    /// The audio lists the game master sent that reached `player`. It sends one each time it applied
    /// a player's list.
    private static func audioListCount(to player: LinkedGameEnvironment.Player, in env: LinkedGameEnvironment) -> Int {
        env.deliveries(to: player).filter { $0.type == .update && $0.subType == .audioList }.count
    }

    // MARK: What crossed the link

    /// The audio items whose bytes went to `player`, in the order they were sent.
    private static func packageIds(to player: LinkedGameEnvironment.Player, in env: LinkedGameEnvironment) -> [UUID] {
        env.deliveries(to: player)
            .filter { $0.type == .store && $0.subType == .show && $0.data.type == .audio && $0.data.data != nil }
            .map(\.data.id)
    }

    /// Every message the player got, in order, reduced to what the test cares about.
    private enum Delivery: Hashable {
        case package(UUID)
        case play(UUID, track: UUID?)
    }

    private static func timeline(to player: LinkedGameEnvironment.Player, in env: LinkedGameEnvironment) -> [Delivery] {
        env.deliveries(to: player).compactMap { message in
            guard message.data.type == .audio else { return nil }
            if message.type == .store, message.subType == .show, message.data.data != nil {
                return .package(message.data.id)
            }
            if message.type == .update, message.subType == .playAudio,
               let request = AudioPlayRequest.decodeData(of: message.data.data) {
                return .play(request.id, track: request.trackId)
            }
            return nil
        }
    }

    private static func playlist(of player: LinkedGameEnvironment.Player) -> [UUID] {
        player.root.audioRoot.audioController.model.playList.map(\.id)
    }

    // MARK: Tests

    @Test("Only the playlist item and its first track are sent before the playlist plays")
    func onlyTheStartItemsAreSentBeforeThePlay() async throws {
        let setup = try await Self.setup()
        let (env, player, playlist) = (setup.env, setup.player, setup.playlist)

        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()

        let timeline = Self.timeline(to: player, in: env)
        let playIndex = try #require(timeline.firstIndex { if case .play = $0 { true } else { false } })
        // Before the play: the item and the first track, nothing else.
        #expect(Set(timeline[..<playIndex]) == [.package(playlist.rootId), .package(playlist.trackIds[0])])
        #expect(timeline[..<playIndex].count == 2)
        // The play starts that track on the player's device. The second track may already follow
        // (it is sent ahead), but never the others.
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: player).first == playlist.trackIds[0] })
        #expect(player.root.audioRoot.audioController.model.currentId == playlist.trackIds[0])
        #expect(Self.playlist(of: player).count <= 2)
        for trackId in playlist.trackIds.dropFirst(2) {
            #expect(player.root.audioRoot.itemController.itemSync(for: trackId, noGame: true) == nil)
            #expect(!Self.packageIds(to: player, in: env).contains(trackId))
        }
    }

    @Test("The next track is sent while the first one plays, one at a time")
    func theNextTrackIsSentAhead() async throws {
        let setup = try await Self.setup()
        let (env, player, playlist) = (setup.env, setup.player, setup.playlist)

        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()

        // The master's track started: the second track follows on its own.
        #expect(await waitUntil(timeout: Self.patience) { Self.packageIds(to: player, in: env).contains(playlist.trackIds[1]) })
        let timeline = Self.timeline(to: player, in: env)
        let playIndex = try #require(timeline.firstIndex { if case .play = $0 { true } else { false } })
        let secondIndex = try #require(timeline.firstIndex(of: .package(playlist.trackIds[1])))
        #expect(secondIndex > playIndex)

        // It joins the playlist that plays, and nothing else is sent.
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: player) == Array(playlist.trackIds.prefix(2)) })
        #expect(player.root.audioRoot.audioController.model.currentId == playlist.trackIds[0])
        #expect(!Self.packageIds(to: player, in: env).contains(playlist.trackIds[2]))
        #expect(!Self.packageIds(to: player, in: env).contains(playlist.trackIds[3]))
    }

    @Test("A skip to a track the player lacks sends the track first and plays it after its receipt")
    func aSkipWaitsForTheTrack() async throws {
        let setup = try await Self.setup()
        let (env, player, playlist) = (setup.env, setup.player, setup.playlist)
        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: player) == Array(playlist.trackIds.prefix(2)) })
        let before = Self.timeline(to: player, in: env).count

        // Jump over the second track to the fourth, which no player has.
        let jump = AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: playlist.trackIds[3])
        await env.master.game(message: jump.command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()

        let after = Array(Self.timeline(to: player, in: env).dropFirst(before))
        let packageIndex = try #require(after.firstIndex(of: .package(playlist.trackIds[3])))
        let playIndex = try #require(after.firstIndex(of: .play(playlist.rootId, track: playlist.trackIds[3])))
        #expect(packageIndex < playIndex)
        // Not the third one: it is not needed for this play.
        #expect(!after.contains(.package(playlist.trackIds[2])))
        // The player plays the fourth track, the playlist keeps the master's order.
        #expect(await waitUntil(timeout: Self.patience) { player.root.audioRoot.audioController.model.currentId == playlist.trackIds[3] })
        #expect(Self.playlist(of: player) == [playlist.trackIds[0], playlist.trackIds[1], playlist.trackIds[3]])
    }

    @Test("A play of what the player already has sends nothing again")
    func aPlayerThatHasTheTracksGetsNoPackage() async throws {
        let setup = try await Self.setup()
        let (env, player, playlist) = (setup.env, setup.player, setup.playlist)
        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: player) == Array(playlist.trackIds.prefix(2)) })
        // The look-ahead of the first play is done, so it cannot send its package after the reset.
        await env.master.waitForAudioPrefetch()
        env.clearHistory()

        // The playlist plays again, and the second track again.
        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()
        let second = AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: playlist.trackIds[1])
        await env.master.game(message: second.command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()

        // The play itself needs no package. The look-ahead of the second track's play may send
        // the third one, which is not part of what the play needs.
        #expect(Self.packageIds(to: player, in: env).filter { !playlist.trackIds.dropFirst(2).contains($0) }.isEmpty)
        let plays = Self.timeline(to: player, in: env).filter { if case .play = $0 { true } else { false } }
        #expect(plays.count == 2)
    }

    @Test("A pause is sent without any package")
    func aPauseSendsNoPackage() async throws {
        let setup = try await Self.setup()
        let (env, player, playlist) = (setup.env, setup.player, setup.playlist)

        await env.master.game(
            message: AudioPlayRequest(id: playlist.rootId, shouldPlay: false, trackId: playlist.trackIds[2]).command,
            actionType: .playAudio
        )
        await env.master.waitForAudioDeliveries()

        #expect(Self.packageIds(to: player, in: env).isEmpty)
    }

    @Test("A player that joins later gets the first track alone before the play, whatever the master played before")
    func aPlayerWhoJoinsLaterGetsTheStartItems() async throws {
        let setup = try await Self.setup()
        let (env, playlist) = (setup.env, setup.playlist)
        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()
        // The look-ahead of the first play is done: the first player has both tracks.
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: setup.player) == Array(playlist.trackIds.prefix(2)) })

        let late = try await env.addPlayer(named: "Player - 2")
        late.root.adventureRoot.startGame()
        await Self.join(late, in: env)
        env.clearHistory()
        await env.master.game(message: AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command, actionType: .playAudio)
        await env.master.waitForAudioDeliveries()

        // The play follows the receipts of the start items, which arrive on their own.
        #expect(await waitUntil(timeout: Self.patience) { Self.timeline(to: late, in: env).contains { if case .play = $0 { true } else { false } } })
        // Before the play the late player got the start items only.
        let timeline = Self.timeline(to: late, in: env)
        let playIndex = try #require(timeline.firstIndex { if case .play = $0 { true } else { false } })
        #expect(Set(timeline[..<playIndex]) == [.package(playlist.rootId), .package(playlist.trackIds[0])])
        #expect(timeline[..<playIndex].count == 2)
        #expect(await waitUntil(timeout: Self.patience) { Self.playlist(of: late).first == playlist.trackIds[0] })
        // The first player has what it needs: no package before the play.
        let first = Self.timeline(to: setup.player, in: env)
        let firstPlay = try #require(first.firstIndex { if case .play = $0 { true } else { false } })
        #expect(first[..<firstPlay].isEmpty)
        // And never one of the tracks behind the second.
        for trackId in playlist.trackIds.dropFirst(2) {
            #expect(!Self.packageIds(to: late, in: env).contains(trackId))
        }
    }
}
#endif
