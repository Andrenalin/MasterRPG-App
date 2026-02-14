// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

public protocol AudioGameStoreable {
    func play(id: UUID?, shouldPlay: Bool) -> Task<Void, Error>

    @MainActor func audioList(allPlayers: Bool, with masterId: UUID) -> NetworkCodableDataType
    @MainActor func applyAudio(id: UUID, for players: [UUID])
    @MainActor func applyAudioList(data: NetworkCodableDataType, for playerId: UUID)
    func play(with data: NetworkCodableDataType) -> Task<Void, Error>
    @MainActor func requestPlay(id: UUID) -> NetworkCodableDataType
}

struct GameController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController, audioController: AudioController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        
        self.audioController = audioController
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }

    let itemController: ItemController
    let exportController: ExportController

    let audioController: AudioController
    let gameModel: ItemGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> AudioModel {
        (gameModel.itemData[itemId] as? AudioModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> AudioModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func allPlayersReported(for id: UUID, deep: Int = 0) -> Bool {
        guard deep < 10 else { return false }
        let item = gameItem(for: id)
        guard gameModel.currentPlayers.filter({ !item.players.contains($0) }).isEmpty else { return false }
        for entry in item.entries {
            if !allPlayersReported(for: entry.audioId, deep: deep + 1) {
                return false
            }
        }
        return true
    }
    
    @MainActor func report(itemId: UUID, for player: UUID) {
        let item = gameItem(for: itemId)
        if !item.players.contains(player) {
            item.players.append(player)
            for entry in item.entries {
                report(itemId: entry.audioId, for: player)
            }
        }
    }
}

extension GameController {
    func audioAsset(for itemId: UUID) async -> PlaylistItem? {
        let item = await gameItem(for: itemId)
        guard let fileUrl = item.fileUrl, let fileUrlDataController = itemController.fileUrlDataController else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            _ = await fileUrlDataController.fileDownloaded(for: fileUrl)
            audioAsset = try await fileUrlDataController.url(for: fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                let data = try Data(contentsOf: url)
                let fileExtension = url.pathExtension
                let tempUrl = URL.temporaryDirectory.appending(path: itemId.uuidString).appendingPathExtension(fileExtension)
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                return PlaylistItem(id: itemId, url: asset.url, title: item.name, artist: "MasterRPG", duration: duration)
            }
        } catch {
            Logger.gameController.error("Cannot read audio from file url: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if audioAsset == nil, let data = fileUrl.data {
                let tempUrl = URL.temporaryDirectory.appending(path: itemId.uuidString).appendingPathExtension("mp4")
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                return PlaylistItem(id: itemId, url: asset.url, title: item.name, artist: "MasterRPG", duration: duration)
            }
        } catch {
            Logger.gameController.error("Cannot read audio from data: \(error.localizedDescription, privacy: .public)")
        }
        return audioAsset
    }

    @MainActor
    func isPlayingPlaylist(id: UUID) -> Bool {
        guard audioController.model.isPlaying else { return false }
        let list = fetchPlaylist(id: id)
        return list.map { $0.id }.contains(audioController.model.currentId)
    }

    @MainActor
    func fetchPlaylist(id: UUID) -> [AudioModel] {
        var seenIds = Set<UUID>()
        return fetchPlaylist(id: id, seenIds: &seenIds)
    }

    @MainActor
    private func fetchPlaylist(id: UUID, seenIds: inout Set<UUID>) -> [AudioModel] {
        guard !seenIds.contains(id) else { return [] }

        var list: [AudioModel] = []
        seenIds.insert(id)
        let item = gameItem(for: id)
        if item.fileUrl != nil {
            list.append(item)
        }
        item.entries.forEach {
            list.append(contentsOf: fetchPlaylist(id: $0.audioId, seenIds: &seenIds))
        }
        return list
    }
}

extension GameController: AudioGameStoreable {
    @discardableResult
    func play(id: UUID?, shouldPlay: Bool) -> Task<Void, Error> {
        Task { @MainActor in
            guard let id else { return }
            let list = fetchPlaylist(id: id)
            await audioController.add(audio: fetchPlaylist(id: id), replace: true)
            audioController.togglePlay(id: list.first?.id)
        }
    }
    
    @MainActor
    func audioList(allPlayers: Bool, with masterId: UUID) -> NetworkCodableDataType {
        let request: AudioListRequest
        if allPlayers {
            var players: [UUID: [UUID]] = [:]
            itemController.itemDataModel.items.forEach {
                applyAudio(id: $0, for: [masterId])
                players[$0] = gameItem(for: $0).players
            }
            request = AudioListRequest(list: [], players: players)
        } else {
            itemController.itemDataModel.items.forEach {
                applyAudio(id: $0, for: [masterId])
            }
            request = AudioListRequest(list: itemController.itemDataModel.items, players: [:])
        }
        let data = request.encodeData()
        return NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: data)
    }
    
    @MainActor
    func applyAudio(id: UUID, for players: [UUID]) {
        let item = gameItem(for: id)
        players.forEach {
            resetAudio(item: item, playerId: $0)
        }
    }

    @MainActor
    func applyAudioList(data: NetworkCodableDataType, for playerId: UUID) {
        guard let list = AudioListRequest.decodeData(of: data.data) else { return }
        applyAudioList(list: list.list, to: playerId)
        list.players.forEach {
            applyAudio(id: $0.key, for: $0.value)
        }
    }
    
    @MainActor
    private func applyAudioList(list: [UUID], to playerId: UUID) {
        list.forEach {
            applyAudio(id: $0, for: [playerId])
        }
    }
    
    private func resetAudio(item: AudioModel, playerId: UUID) {
        if !item.players.contains(playerId) {
            item.players.append(playerId)
        }
    }
    
    
    func play(with data: NetworkCodableDataType) -> Task<Void, Error> {
        let request = AudioPlayRequest.decodeData(of: data.data)
        return play(id: request?.id, shouldPlay: request?.shouldPlay ?? false)
    }

    @MainActor
    func requestPlay(id: UUID) -> NetworkCodableDataType {
        let requestData = AudioPlayRequest(id: id, shouldPlay: !(audioController.model.currentId == id && audioController.model.isPlaying))
        return NetworkCodableDataType(id: id, type: .audio, version: 0, data: requestData.encodeData())
    }
}

struct AudioPlayRequest: Codable {
    let id: UUID
    let shouldPlay: Bool
}

extension AudioPlayRequest {
    static func decodeData(of data: Data?) -> AudioPlayRequest? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(AudioPlayRequest.self, from: data)
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}

struct AudioListRequest: Codable {
    let list: [UUID]
    let players: [UUID: [UUID]]
}

extension AudioListRequest {
    static func decodeData(of data: Data?) -> AudioListRequest? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(AudioListRequest.self, from: data)
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}
