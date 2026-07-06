// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

@MainActor
struct GameControllerTests {
    @Test func playlistReportsAndNetworkRequests() async throws {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        let sut = root.gameController
        let masterId = UUID()
        let playerId = UUID()
        let otherPlayerId = UUID()
        let trackAId = UUID()
        let trackBId = UUID()
        let playlistId = UUID()
        let trackA = AudioModel(id: trackAId, name: "Track A", fileUrl: Self.fileUrl(for: trackAId))
        let trackB = AudioModel(id: trackBId, name: "Track B", fileUrl: Self.fileUrl(for: trackBId))
        let playlist = AudioModel(
            id: playlistId,
            name: "Playlist",
            entries: [
                AudioEntryModel(id: UUID(), audioId: trackAId),
                AudioEntryModel(id: UUID(), audioId: trackBId)
            ]
        )

        root.itemController.replace(model: trackA, isInsert: true)
        root.itemController.replace(model: trackB, isInsert: true)
        root.itemController.replace(model: playlist, isInsert: true)

        sut.setGame(item: playlist.copy(), itemId: playlistId)

        #expect(sut.currentItem().id == playlistId)
        #expect(sut.gameItem(for: trackAId).id == trackAId)
        #expect(sut.fetchPlaylist(id: playlistId).map(\.id) == [trackAId, trackBId])

        sut.gameModel.setCurrent(players: [playerId, otherPlayerId])
        #expect(!sut.allPlayersReported(for: playlistId))

        sut.report(itemId: playlistId, for: playerId)
        sut.report(itemId: playlistId, for: playerId)
        #expect(sut.gameModel.playerReport(for: playlistId) == [playerId])
        #expect(sut.gameModel.playerReport(for: trackAId) == [playerId])
        #expect(sut.gameModel.playerReport(for: trackBId) == [playerId])

        sut.report(itemId: playlistId, for: otherPlayerId)
        #expect(sut.allPlayersReported(for: playlistId))

        let allPlayersData = sut.audioList(allPlayers: true, with: masterId)
        let allPlayersRequest = try #require(AudioListRequest.decodeData(of: allPlayersData.data))
        #expect(allPlayersRequest.list.isEmpty)
        #expect(allPlayersRequest.players[trackAId]?.contains(masterId) == true)

        let listData = sut.audioList(allPlayers: false, with: masterId)
        let listRequest = try #require(AudioListRequest.decodeData(of: listData.data))
        #expect(listRequest.list.contains(trackAId))
        #expect(listRequest.players.isEmpty)

        let incomingList = AudioListRequest(list: [playlistId], players: [trackBId: [otherPlayerId]])
        sut.applyAudioList(
            data: NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: incomingList.encodeData()),
            for: playerId
        )
        #expect(sut.gameModel.playerReport(for: playlistId).contains(playerId))
        #expect(sut.gameModel.playerReport(for: trackBId).contains(otherPlayerId))

        let playRequest = try #require(AudioPlayRequest.decodeData(of: sut.requestPlay(id: playlistId).data))
        #expect(playRequest.id == playlistId)
        #expect(playRequest.shouldPlay)

        try await sut.play(id: nil, shouldPlay: true).value
        try await sut.play(id: playlistId, shouldPlay: false).value
    }
}

private extension GameControllerTests {
    static func fileUrl(for id: UUID) -> FileUrl {
        FileUrl(fileId: id, url: URL(filePath: "/tmp/\(id.uuidString).m4a"), location: .local, module: "audio", relativeUrl: nil)
    }
}
