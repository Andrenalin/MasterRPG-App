// @copyright André Trettin

import AVFoundation
import CoreRPG
import Foundation
import Observation
import os.log

public protocol AudioGameStoreable: GameControllable {
    func play(id: UUID?, shouldPlay: Bool) -> Task<Void, Error>

    @MainActor func audioList(allPlayers: Bool, with masterId: UUID) -> NetworkCodableDataType
    @MainActor func applyAudio(id: UUID, for players: [UUID])
    @MainActor func applyAudioList(data: NetworkCodableDataType, for playerId: UUID)
    func play(with data: NetworkCodableDataType) -> Task<Void, Error>
    @MainActor func requestPlay(id: UUID) -> NetworkCodableDataType
}

struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController, audioController: AudioController) {
        self.itemController = itemController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, fileUrlDataController: fileUrlDataController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, fileUrlDataController: fileUrlDataController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.audioController = audioController
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    let audioController: AudioController
    
    let gameModel: ItemGameModel
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    var importControllable: any ImportControllable {
        importController as ImportControllable
    }
//    var rootExportControllable: any ExportControllable {
//        root.rootControllable.gameExportControllable
//    }
//    var rootImportControllable: any ImportControllable {
//        root.rootControllable.gameImportControllable
//    }
    
    @MainActor
    func allPlayersReported(for id: UUID, deep: Int) -> Bool {
        guard deep < 10 else { return false }
        guard gameModel.reports[id] == gameModel.currentPlayers else { return false }
        guard let entries = gameItem(for: id)?.entries else { return true }
        for entry in entries {
            if !allPlayersReported(for: entry.childId, deep: deep + 1) {
                return false
            }
        }
        return true
    }
    
    @MainActor
    func report(itemId: UUID, for player: UUID) {
        var reports = gameModel.reports[itemId, default: []]
        if !reports.contains(player) {
            reports.append(player)
            reports.sort()
            let entries = gameItem(for: itemId)?.entries ?? []
            for entry in entries {
                report(itemId: entry.childId, for: player)
            }
        }
    }
}

extension GameController {
    func audioAsset(for itemId: UUID) async -> PlaylistItem? {
        guard let item = await gameItem(for: itemId), let fileUrl = item.fileUrl else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            _ = await exportControllable.fileUrlDataController?.fileDownloaded(for: fileUrl)
            audioAsset = try await exportControllable.fileUrlDataController?.url(for: fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                let data = try Data(contentsOf: url)
                let fileExtension = url.pathExtension
                let tempUrl = URL.temporaryDirectory.appending(path: itemId.uuidString).appendingPathExtension(fileExtension)
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                return PlaylistItem(id: itemId, url: asset.url, title: item.name.wrappedValue, artist: "MasterRPG", duration: duration)
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
                return PlaylistItem(id: itemId, url: asset.url, title: item.name.wrappedValue, artist: "MasterRPG", duration: duration)
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
    func fetchPlaylist(id: UUID) -> [ItemDataCodableModel] {
        var seenIds = Set<UUID>()
        return fetchPlaylist(id: id, seenIds: &seenIds)
    }

    @MainActor
    private func fetchPlaylist(id: UUID, seenIds: inout Set<UUID>) -> [ItemDataCodableModel] {
        guard !seenIds.contains(id) else { return [] }

        var list: [ItemDataCodableModel] = []
        seenIds.insert(id)
        if let item = gameItem(for: id) {
            if item.fileUrl != nil {
                list.append(item)
            }
            item.entries.forEach {
                list.append(contentsOf: fetchPlaylist(id: $0.childId, seenIds: &seenIds))
            }
        }
        return list
    }
}

extension GameController: AudioGameStoreable {
    @discardableResult
    func play(id: UUID?, shouldPlay: Bool) -> Task<Void, Error> {
        Task {
            guard let id else { return }
            await audioController.add(audio: fetchPlaylist(id: id), replace: true)
            guard shouldPlay else { return }
            await audioController.preparePlay(id: id)
        }
    }
    
    @MainActor
    func audioList(allPlayers: Bool, with masterId: UUID) -> NetworkCodableDataType {
        let request: AudioListRequest
        if allPlayers {
            var players: [UUID: [UUID]] = [:]
            itemController.allItemIds().forEach {
                applyAudio(id: $0, for: [masterId])
                players[$0] = gameModel.reports[$0, default: []]
            }
            request = AudioListRequest(list: [], players: players)
        } else {
            itemController.allItemIds().forEach {
                applyAudio(id: $0, for: [masterId])
            }
            request = AudioListRequest(list: itemController.allItemIds(), players: [:])
        }
        let data = request.encodeData()
        return NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: data)
    }
    
    @MainActor
    func applyAudio(id: UUID, for players: [UUID]) {
        players.forEach {
            report(itemId: id, for: $0)
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
