// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

public protocol AudioGameStoreable {
    func play(id: UUID?, shouldPlay: Bool) -> Task<Void, Error>
    /// Loads the playlist for `id` and prepares the first item for coordinator sync
    /// without triggering play locally. Used in SharePlay mode where
    /// AVPlayerPlaybackCoordinator propagates play() from the initiating device.
    @MainActor func loadPlaylist(id: UUID) async

    @MainActor func audioList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @MainActor func applyAudio(id: UUID, for players: [UUID])
    @discardableResult
    @MainActor func applyAudioList(data: NetworkCodableDataType, for playerId: UUID, authoritative: Bool) -> Bool
    @MainActor func missingPlayers(for itemId: UUID) -> [UUID]
    func hasLocalAudioData(for itemId: UUID) async -> Bool
    func play(with data: NetworkCodableDataType) -> Task<Void, Error>
    func shouldPlay(with data: NetworkCodableDataType) -> Bool
    @MainActor func requestPlay(id: UUID) -> NetworkCodableDataType
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, audioController: AudioController, exportController: ExportController) {
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
    private func fileUrlAndName(of item: AudioModel) -> (FileUrl?, String) {
        (item.fileUrl, item.name)
    }

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
        let players = gameModel.playerReport(for: id)
        guard gameModel.currentPlayers.filter({ !players.contains($0) }).isEmpty else { return false }
        for entry in item.entries {
            if !allPlayersReported(for: entry.audioId, deep: deep + 1) {
                return false
            }
        }
        return true
    }

    @MainActor func missingPlayers(for itemId: UUID) -> [UUID] {
        missingPlayers(for: itemId, visited: []).sorted()
    }

    @MainActor private func missingPlayers(for itemId: UUID, visited: Set<UUID>) -> Set<UUID> {
        guard !visited.contains(itemId) else { return [] }
        let visited = visited.union([itemId])
        let reported = Set(gameModel.playerReport(for: itemId))
        var missing = Set(gameModel.currentPlayers).subtracting(reported)
        for entry in gameItem(for: itemId).entries {
            missing.formUnion(missingPlayers(for: entry.audioId, visited: visited))
        }
        return missing
    }

    @MainActor func report(itemId: UUID, for player: UUID) {
        report(itemId: itemId, for: player, visited: [])
    }

    @MainActor private func report(itemId: UUID, for player: UUID, visited: Set<UUID>) {
        guard !visited.contains(itemId) else { return }
        let visited = visited.union([itemId])
        let item = gameItem(for: itemId)
        let players = gameModel.playerReport(for: itemId)
        if !players.contains(player) {
            gameModel.setPlayerReport(playerId: player, for: itemId)
        }
        for entry in item.entries {
            report(itemId: entry.audioId, for: player, visited: visited)
        }
    }
}

extension GameController {
    func hasLocalAudioData(for itemId: UUID) async -> Bool {
        await hasLocalAudioData(for: itemId, visited: [])
    }

    private func hasLocalAudioData(for itemId: UUID, visited: Set<UUID>) async -> Bool {
        guard !visited.contains(itemId) else { return true }
        let visited = visited.union([itemId])

        let item = await gameItem(for: itemId)
        // `item.entries` is itself `@MainActor` (inherited from `AudioModel`'s class
        // annotation) — `await` alone hops there, no `MainActor.run` wrapper needed.
        let entryIds = await item.entries.map(\.audioId)
        guard await hasLocalFileData(for: itemId) else { return false }

        for entryId in entryIds {
            guard await hasLocalAudioData(for: entryId, visited: visited) else { return false }
        }
        return true
    }

    @MainActor
    private func hasLocalDatabaseAudioData(for itemId: UUID, visited: Set<UUID> = []) async -> Bool {
        guard !visited.contains(itemId) else { return true }
        guard let item = itemController.itemSync(for: itemId, noGame: true) else { return false }
        let visited = visited.union([itemId])

        if let fileUrl = item.fileUrl,
           let fileUrlDataController = itemController.fileUrlDataController,
           await !fileUrlDataController.hasLocalData(for: fileUrl) {
            return false
        }

        for entryId in item.entries.map(\.audioId) {
            guard await hasLocalDatabaseAudioData(for: entryId, visited: visited) else { return false }
        }
        return true
    }

    func audioAsset(for itemId: UUID) async -> PlaylistItem? {
        let item = await gameItem(for: itemId)
        // Extract the Sendable fields on the MainActor — the @MainActor model must
        // not be read inside the file-loading closures below.
        let (itemFileUrl, title) = await fileUrlAndName(of: item)
        guard let fileUrl = itemFileUrl, let fileUrlDataController = itemController.fileUrlDataController else { return nil }

        var audioAsset: PlaylistItem? = nil
        do {
            _ = await fileUrlDataController.fileDownloaded(for: fileUrl)
            audioAsset = try await fileUrlDataController.url(for: fileUrl) { url -> PlaylistItem? in
                guard let url else { return nil }
                // Use ResourceCache for better performance
                let key = "audio.game.\(itemId.uuidString)"
                let data = try await ResourceCache.shared.load(key: key, from: url)
                let fileExtension = url.pathExtension
                let tempUrl = URL.temporaryDirectory.appending(path: itemId.uuidString).appendingPathExtension(fileExtension)
                try data.write(to: tempUrl)
                let asset = AVURLAsset(url: tempUrl)
                let duration = try await asset.load(.duration)
                return PlaylistItem(id: itemId, url: asset.url, title: title, artist: "MasterRPG", duration: duration)
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
                return PlaylistItem(id: itemId, url: asset.url, title: title, artist: "MasterRPG", duration: duration)
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
            guard shouldPlay else {
                audioController.pause()
                return
            }
            let list = fetchPlaylist(id: id)
            await audioController.add(audio: list, replace: true)
            audioController.togglePlay(id: list.first?.id, triggerPlay: true)
        }
    }

    @MainActor
    func loadPlaylist(id: UUID) async {
        let list = fetchPlaylist(id: id)
        await audioController.add(audio: list, replace: true)
        if let firstId = list.first?.id {
            await audioController.preparePlay(id: firstId, triggerPlay: false)
        }
    }
    
    @MainActor
    func audioList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let request: AudioListRequest
        if allPlayers {
            var players: [UUID: [UUID]] = [:]
            let itemIds = Set(itemController.itemDataModel.items).union(gameModel.playerReports.keys)
            for itemId in itemIds {
                if await hasLocalDatabaseAudioData(for: itemId) {
                    applyAudio(id: itemId, for: [masterId])
                }
                players[itemId] = gameModel.playerReport(for: itemId)
            }
            request = AudioListRequest(list: [], players: players)
        } else {
            var availableItems: [UUID] = []
            for itemId in itemController.itemDataModel.items {
                guard await hasLocalDatabaseAudioData(for: itemId) else { continue }
                applyAudio(id: itemId, for: [masterId])
                availableItems.append(itemId)
            }
            request = AudioListRequest(list: availableItems, players: [:])
        }
        let data = request.encodeData()
        return NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: data)
    }
    
    @MainActor
    func applyAudio(id: UUID, for players: [UUID]) {
        players.forEach {
            gameModel.setPlayerReport(playerId: $0, for: id)
        }
    }

    @MainActor
    @discardableResult
    func applyAudioList(data: NetworkCodableDataType, for playerId: UUID, authoritative: Bool) -> Bool {
        guard let list = AudioListRequest.decodeData(of: data.data) else { return false }
        if authoritative {
            let itemIds = Set(itemController.itemDataModel.items)
                .union(gameModel.playerReports.keys)
                .union(list.players.keys)
            for itemId in itemIds {
                gameModel.playerReports[itemId] = list.players[itemId] ?? []
            }
        } else {
            let reportedItems = Set(list.list)
            let itemIds = Set(itemController.itemDataModel.items)
                .union(gameModel.playerReports.keys)
                .union(reportedItems)
            for itemId in itemIds {
                var players = gameModel.playerReport(for: itemId).filter { $0 != playerId }
                if reportedItems.contains(itemId) {
                    players.append(playerId)
                }
                gameModel.playerReports[itemId] = players
            }
        }
        return true
    }
    
    func play(with data: NetworkCodableDataType) -> Task<Void, Error> {
        let request = AudioPlayRequest.decodeData(of: data.data)
        return play(id: request?.id, shouldPlay: request?.shouldPlay ?? false)
    }

    func shouldPlay(with data: NetworkCodableDataType) -> Bool {
        AudioPlayRequest.decodeData(of: data.data)?.shouldPlay ?? false
    }

    @MainActor
    func requestPlay(id: UUID) -> NetworkCodableDataType {
        // Use isPlayingPlaylist rather than comparing currentId == id:
        // currentId is the active *track*, but id is the playlist root item,
        // so a direct comparison almost always returns false even when playing.
        let requestData = AudioPlayRequest(id: id, shouldPlay: !isPlayingPlaylist(id: id))
        return NetworkCodableDataType(id: id, type: .audio, version: 0, data: requestData.encodeData())
    }
}

struct AudioPlayRequest: Codable, Sendable, MessageMapper {
    let id: UUID
    let shouldPlay: Bool
}

struct AudioListRequest: Codable, Sendable, MessageMapper {
    let list: [UUID]
    let players: [UUID: [UUID]]
}
