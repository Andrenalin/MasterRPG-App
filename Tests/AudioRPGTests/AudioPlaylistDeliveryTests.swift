// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

/// A playlist is not sent as one package: the game master sends the playlist item and its first
/// track, and every other track on its own, ahead of its play. These tests cover what that means
/// for the export, the import, who has what, and what a device plays. A playlist of many files
/// cannot travel at once (SharePlay uploads one file per Journal slot).
@Suite("Audio playlist delivery")
@MainActor
struct AudioPlaylistDeliveryTests {
    /// A playlist item without a file of its own and the tracks it lists, in the master's library.
    private struct Playlist {
        let rootId: UUID
        let trackIds: [UUID]
    }

    /// Real audio bytes, so the tracks load like real ones.
    private static func audioData() async throws -> Data {
        let source = try await MockRoot.importTestData()
        var found: FileUrl?
        for id in source.itemController.itemDataModel.items {
            if let fileUrl = source.itemController.itemSync(for: id)?.fileUrl {
                found = fileUrl
                break
            }
        }
        let fileUrl = try #require(found)
        let controller = try #require(source.itemController.fileUrlDataController)
        return try #require(await controller.loadData(for: fileUrl))
    }

    private static func insertPlaylist(into root: AudioRootModel, trackCount: Int, audio: Data) throws -> Playlist {
        var trackIds: [UUID] = []
        for number in 1...trackCount {
            let id = UUID()
            let url = URL.temporaryDirectory.appending(path: "playlist-\(id.uuidString).m4a")
            try audio.write(to: url)
            let fileUrl = FileUrl(fileId: id, url: url, location: .local, module: NetworkModules.audio.token, relativeUrl: nil)
            root.itemController.replace(model: AudioModel(id: id, name: "Track \(number)", fileUrl: fileUrl), isInsert: true)
            trackIds.append(id)
        }
        let rootId = UUID()
        root.itemController.replace(
            model: AudioModel(
                id: rootId,
                name: "Playlist",
                entries: trackIds.map { AudioEntryModel(id: UUID(), audioId: $0) }
            ),
            isInsert: true
        )
        return Playlist(rootId: rootId, trackIds: trackIds)
    }

    /// What the game master sends one device: the package of `id`, stored the way a player stores
    /// a delivery.
    private static func deliver(_ id: UUID, from master: AudioRootModel, to player: AudioRootModel) async throws {
        let package = try await master.gameController.createGameData(for: id)
        try await player.gameController.updateGame(data: package, hide: false, deep: true)
        await player.audioGameControllable.itemArrived(id: id)
    }

    private static func masterAndPlayer(trackCount: Int = 4) async throws -> (master: AudioRootModel, player: AudioRootModel, playlist: Playlist) {
        let audio = try await audioData()
        let master = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: master)
        let playlist = try insertPlaylist(into: master, trackCount: trackCount, audio: audio)
        let player = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: player)
        return (master, player, playlist)
    }

    // MARK: Export

    @Test("A package for players holds the item alone, a library export holds the whole playlist")
    func exportForPlayersHoldsTheItemAlone() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()
        let module = master.itemController.config.module

        let forOwner = master.exportControllable.exporting(ids: [playlist.rootId])
        let forPlayers = ExportAudience.$current.withValue(.players) {
            master.exportControllable.exporting(ids: [playlist.rootId])
        }

        #expect(Set(forOwner.ids[module] ?? []) == Set([playlist.rootId] + playlist.trackIds))
        #expect(forPlayers.ids[module] == [playlist.rootId])
    }

    @Test("A package for players holds a track without the tracks it links")
    func exportOfALinkingTrackHoldsNoOtherTrack() async throws {
        let root = try await MockRoot.importTestData()
        let linking = try #require(root.itemController.itemDataModel.items.first {
            root.itemController.itemSync(for: $0)?.entries.isEmpty == false
        })
        let module = root.itemController.config.module

        let forPlayers = ExportAudience.$current.withValue(.players) {
            root.exportControllable.exporting(ids: [linking])
        }

        #expect(forPlayers.ids[module] == [linking])
    }

    // MARK: Import

    @Test("A player that received the playlist item has no track yet")
    func importedPlaylistItemHoldsNoTrack() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()

        try await Self.deliver(playlist.rootId, from: master, to: player)

        #expect(player.itemController.itemDataModel.items.count == 1)
        // The list of tracks arrived, the tracks themselves did not.
        #expect(player.gameController.gameItem(for: playlist.rootId).entries.map(\.audioId) == playlist.trackIds)
        #expect(player.gameController.fetchPlaylist(id: playlist.rootId).isEmpty)
        for trackId in playlist.trackIds {
            #expect(player.itemController.itemSync(for: trackId, noGame: true) == nil)
        }
    }

    @Test("Every track arrives as an item of its own and joins the playlist in order")
    func tracksArriveOneByOne() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()
        try await Self.deliver(playlist.rootId, from: master, to: player)

        try await Self.deliver(playlist.trackIds[0], from: master, to: player)
        #expect(player.gameController.fetchPlaylist(id: playlist.rootId).map(\.id) == [playlist.trackIds[0]])
        #expect(player.itemController.itemDataModel.items.count == 2)

        // The second package does not bring the third one along.
        try await Self.deliver(playlist.trackIds[1], from: master, to: player)
        #expect(player.gameController.fetchPlaylist(id: playlist.rootId).map(\.id) == Array(playlist.trackIds.prefix(2)))
        #expect(player.itemController.itemSync(for: playlist.trackIds[2], noGame: true) == nil)
    }

    // MARK: What a playlist needs, and who has it

    @Test("A playlist needs its item and its first track to start")
    func startItems() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()

        #expect(master.gameController.startItemIds(for: playlist.rootId) == [playlist.rootId, playlist.trackIds[0]])
        // A track is its own start.
        #expect(master.gameController.startItemIds(for: playlist.trackIds[2]) == [playlist.trackIds[2]])
        // Nothing to send for an unknown item beyond itself.
        let unknown = UUID()
        #expect(master.gameController.startItemIds(for: unknown) == [unknown])
    }

    @Test("A playlist item with a file of its own is its own first track")
    func startItemsOfAPlaylistItemWithAFile() async throws {
        let root = try await MockRoot.importTestData()
        let linking = try #require(root.itemController.itemDataModel.items.first {
            root.itemController.itemSync(for: $0)?.entries.isEmpty == false
        })

        #expect(root.gameController.startItemIds(for: linking) == [linking])
    }

    @Test("A play command needs the start items and the track it names, a pause nothing")
    func requiredItems() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()
        let audio = master.gameController

        let plainPlay = AudioPlayRequest(id: playlist.rootId, shouldPlay: true).command
        #expect(audio.requiredItemIds(for: plainPlay) == [playlist.rootId, playlist.trackIds[0]])

        let nextTrack = AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: playlist.trackIds[2]).command
        #expect(audio.requiredItemIds(for: nextTrack) == [playlist.rootId, playlist.trackIds[0], playlist.trackIds[2]])

        let firstTrack = AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: playlist.trackIds[0]).command
        #expect(audio.requiredItemIds(for: firstTrack) == [playlist.rootId, playlist.trackIds[0]])

        let foreignTrack = AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: UUID()).command
        #expect(audio.requiredItemIds(for: foreignTrack) == [playlist.rootId, playlist.trackIds[0]])

        let pause = AudioPlayRequest(id: playlist.rootId, shouldPlay: false, trackId: playlist.trackIds[1]).command
        #expect(audio.requiredItemIds(for: pause).isEmpty)
    }

    @Test("The track after the playing one is the one to send ahead")
    func nextTrackToSendAhead() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()
        let audio = master.gameController

        #expect(audio.nextTrackId(after: playlist.trackIds[0], in: playlist.rootId) == playlist.trackIds[1])
        #expect(audio.nextTrackId(after: playlist.trackIds[2], in: playlist.rootId) == playlist.trackIds[3])
        #expect(audio.nextTrackId(after: playlist.trackIds[3], in: playlist.rootId) == nil)
        #expect(audio.nextTrackId(after: UUID(), in: playlist.rootId) == nil)
    }

    @Test("A player that already has the tracks lacks nothing")
    func aPlayerWithTheTracksLacksNothing() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()
        let audio = master.gameController
        let holder = UUID()
        let missing = UUID()
        audio.gameModel.setCurrent(players: [holder, missing])

        // The join handshake: a player reports every item of its own library that it has.
        let report = AudioListRequest(list: [playlist.rootId] + playlist.trackIds, players: [:])
        #expect(audio.applyAudioList(
            data: NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: report.encodeData()),
            for: holder,
            authoritative: false
        ))

        #expect(audio.missingPlayers(for: playlist.rootId) == [missing])
        for trackId in playlist.trackIds {
            #expect(audio.missingPlayers(ofItem: trackId) == [missing])
        }
        #expect(audio.isAudioAvailable(itemId: playlist.rootId, for: holder))
        #expect(!audio.isAudioAvailable(itemId: playlist.rootId, for: missing))
    }

    @Test("A player that has the first track but not the next one lacks only the next one")
    func aPlayerWithTheFirstTrackLacksTheNextOnly() async throws {
        let (master, _, playlist) = try await Self.masterAndPlayer()
        let audio = master.gameController
        let player = UUID()
        audio.gameModel.setCurrent(players: [player])
        audio.report(itemId: playlist.rootId, for: player)
        audio.report(itemId: playlist.trackIds[0], for: player)

        // The playlist can start, the second track is still to send.
        #expect(audio.missingPlayers(for: playlist.rootId).isEmpty)
        #expect(audio.missingPlayers(ofItem: playlist.trackIds[1]) == [player])
    }

    // MARK: Playing while the tracks arrive

    @Test("A device starts with the first track and the next ones join the playlist while it plays")
    func tracksJoinThePlaylistThatPlays() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()
        try await Self.deliver(playlist.rootId, from: master, to: player)
        try await Self.deliver(playlist.trackIds[0], from: master, to: player)
        let model = player.audioPlayerModel

        try await player.gameController.play(AudioPlayRequest(id: playlist.rootId, shouldPlay: true))

        #expect(model.playList.map(\.id) == [playlist.trackIds[0]])
        #expect(model.currentId == playlist.trackIds[0])
        #expect(model.playListRootId == playlist.rootId)
        let generation = model.playListGeneration

        // The fourth track arrives before the second: the playlist keeps the master's order.
        try await Self.deliver(playlist.trackIds[3], from: master, to: player)
        #expect(model.playList.map(\.id) == [playlist.trackIds[0], playlist.trackIds[3]])
        try await Self.deliver(playlist.trackIds[1], from: master, to: player)
        try await Self.deliver(playlist.trackIds[2], from: master, to: player)

        #expect(model.playList.map(\.id) == playlist.trackIds)
        #expect(model.currentId == playlist.trackIds[0])
        // Nothing was loaded again: the track that plays was not interrupted.
        #expect(model.playListGeneration == generation)
        #expect(model.wantsPlayback)
    }

    @Test("A next command plays a track that arrived after the playlist was loaded")
    func nextPlaysATrackThatArrivedLater() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()
        try await Self.deliver(playlist.rootId, from: master, to: player)
        try await Self.deliver(playlist.trackIds[0], from: master, to: player)
        try await player.gameController.play(AudioPlayRequest(id: playlist.rootId, shouldPlay: true))
        let model = player.audioPlayerModel
        let generation = model.playListGeneration
        try await Self.deliver(playlist.trackIds[1], from: master, to: player)

        try await player.gameController.play(
            AudioPlayRequest(id: playlist.rootId, shouldPlay: true, trackId: playlist.trackIds[1])
        )

        #expect(model.currentId == playlist.trackIds[1])
        #expect(model.playList.map(\.id) == Array(playlist.trackIds.prefix(2)))
        #expect(model.playListGeneration == generation)
    }

    @Test("A track that arrives without a playlist loaded changes nothing")
    func arrivalWithoutAPlaylistChangesNothing() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()

        try await Self.deliver(playlist.rootId, from: master, to: player)
        try await Self.deliver(playlist.trackIds[0], from: master, to: player)

        #expect(player.audioPlayerModel.playList.isEmpty)
        #expect(!player.audioPlayerModel.wantsPlayback)
    }

    @Test("A track of another playlist does not join the playlist that plays")
    func foreignTrackDoesNotJoin() async throws {
        let (master, player, playlist) = try await Self.masterAndPlayer()
        let other = try Self.insertPlaylist(into: master, trackCount: 2, audio: try await Self.audioData())
        try await Self.deliver(playlist.rootId, from: master, to: player)
        try await Self.deliver(playlist.trackIds[0], from: master, to: player)
        try await player.gameController.play(AudioPlayRequest(id: playlist.rootId, shouldPlay: true))

        try await Self.deliver(other.rootId, from: master, to: player)
        try await Self.deliver(other.trackIds[0], from: master, to: player)

        #expect(player.audioPlayerModel.playList.map(\.id) == [playlist.trackIds[0]])
    }
}
#endif
