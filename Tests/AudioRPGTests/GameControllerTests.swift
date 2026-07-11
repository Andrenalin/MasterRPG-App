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
        let trackA = AudioModel(
            id: trackAId,
            name: "Track A",
            fileUrl: try Self.localFileUrl(for: trackAId, fileData: Data("track-a".utf8))
        )
        let trackB = AudioModel(
            id: trackBId,
            name: "Track B",
            fileUrl: try Self.localFileUrl(for: trackBId, fileData: Data("track-b".utf8))
        )
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

        let allPlayersData = await sut.audioList(allPlayers: true, with: masterId)
        let allPlayersRequest = try #require(AudioListRequest.decodeData(of: allPlayersData.data))
        #expect(allPlayersRequest.list.isEmpty)
        #expect(allPlayersRequest.players[trackAId]?.contains(masterId) == true)

        let listData = await sut.audioList(allPlayers: false, with: masterId)
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

    @Test("Game import adds source folder only when audio file is missing locally")
    func gameImportAddsFolderOnlyForMissingAudioFile() async throws {
        let fileData = Data("shared game audio".utf8)
        let exported = try await Self.exportedFolderAudioGameData(fileData: fileData)

        let missingRoot = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: missingRoot)
        missingRoot.itemController.itemDataModel.isGameMode = true

        try await missingRoot.gameController.importNetwork(from: exported.data)

        let missingAudio = try #require(missingRoot.itemController.itemSync(for: exported.audioId))
        let missingFolder = try #require(missingRoot.itemController.itemSync(for: exported.folderId))
        #expect(missingAudio.parentId == exported.folderId)
        #expect(missingFolder.entries.contains { $0.childId == exported.audioId })

        for placement in ExistingAudioPlacement.allCases {
            let existing = try await Self.rootWithExistingAudio(
                audioId: exported.audioId,
                fileData: fileData,
                placement: placement
            )

            existing.root.itemController.itemDataModel.isGameMode = true

            try await existing.root.gameController.importNetwork(from: exported.data)

            let gameAudio = try #require(existing.root.itemController.itemSync(for: exported.audioId))
            let storedAudio = try #require(existing.root.itemController.itemSync(for: exported.audioId, noGame: true))
            #expect(gameAudio.parentId == existing.parentId, "Game import should preserve \(placement.label) placement for an existing local audio file.")
            #expect(storedAudio.parentId == existing.parentId, "Game import must not persistently move an existing local audio file.")
            #expect(existing.root.itemController.itemSync(for: exported.folderId) == nil, "Game import should not add the source folder when the audio file already exists locally.")
        }
    }
}

private extension GameControllerTests {
    enum ExistingAudioPlacement: CaseIterable {
        case noFolder
        case differentFolder

        var label: String {
            switch self {
            case .noFolder: "root-level"
            case .differentFolder: "different-folder"
            }
        }
    }

    static func exportedFolderAudioGameData(fileData: Data) async throws -> (data: Data, audioId: UUID, folderId: UUID) {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)

        let folderId = await root.itemController.addNew(type: .folder)
        root.editController.reset(name: "Source Folder", itemId: folderId)

        let audioId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Source Cue", itemId: audioId)
        root.editController.addItem(itemId: audioId, parentId: folderId)
        try await root.editController.resetFile(data: fileData, itemId: audioId, path: "Source Cue.m4a")

        let gameData = try await root.gameController.createGameData(for: audioId)
        let data = try #require(gameData.data)
        return (data, audioId, folderId)
    }

    static func rootWithExistingAudio(
        audioId: UUID,
        fileData: Data,
        placement: ExistingAudioPlacement
    ) async throws -> (root: AudioRootModel, parentId: UUID?) {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)

        let fileUrl = try localFileUrl(for: audioId, fileData: fileData)
        let audio = AudioModel(id: audioId, name: "Local Cue", fileUrl: fileUrl)
        root.itemController.replace(model: audio, isInsert: true)

        switch placement {
        case .noFolder:
            return (root, nil)
        case .differentFolder:
            let folderId = await root.itemController.addNew(type: .folder)
            root.editController.reset(name: "Local Folder", itemId: folderId)
            root.editController.addItem(itemId: audioId, parentId: folderId)
            return (root, folderId)
        }
    }

    static func localFileUrl(for id: UUID, fileData: Data) throws -> FileUrl {
        let fileUrl = URL.temporaryDirectory
            .appending(path: "existing-\(id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        try fileData.write(to: fileUrl)
        return FileUrl(fileId: id, url: fileUrl, location: .local, module: NetworkModules.audio.token, relativeUrl: nil)
    }

    static func fileUrl(for id: UUID) -> FileUrl {
        FileUrl(fileId: id, url: URL(filePath: "/tmp/\(id.uuidString).m4a"), location: .local, module: "audio", relativeUrl: nil)
    }
}
