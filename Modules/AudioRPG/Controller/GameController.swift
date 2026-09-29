// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

public protocol AudioGameStorable: Sendable {
    // Returning a Task<Void, Error> instead of being async throws let both
    // call sites discard `.result` (and any thrown error) via `let _ =`.
    // See CODE_AUDIT_Game §4.2.
    @MainActor func play(id: UUID?, shouldPlay: Bool) async throws
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
    @MainActor func play(with data: NetworkCodableDataType) async throws
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

}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func allPlayersReported(for id: UUID) -> Bool {
        allPlayersReported(for: id, visited: [])
    }

    // A named recursion depth (`deep < 10`) doesn't actually guard against a
    // playlist cycle, only against a very deep one — switched to the same
    // `visited` cycle guard the rest of this file's playlist traversals
    // (missingPlayers/report/hasLocalAudioData) already use.
    // See CODE_AUDIT_Game §9.14.
    @MainActor private func allPlayersReported(for id: UUID, visited: Set<UUID>) -> Bool {
        guard !visited.contains(id) else { return true }
        let visited = visited.union([id])
        let item = gameItem(for: id)
        let players = gameModel.playerReport(for: id)
        guard gameModel.currentPlayers.filter({ !players.contains($0) }).isEmpty else { return false }
        for entry in item.entries {
            if !allPlayersReported(for: entry.audioId, visited: visited) {
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
           await !fileUrlDataController.hasDownloadedData(for: fileUrl) {
            return false
        }

        for entryId in item.entries.map(\.audioId) {
            guard await hasLocalDatabaseAudioData(for: entryId, visited: visited) else { return false }
        }
        return true
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

extension GameController: AudioGameStorable {
    @MainActor
    func play(id: UUID?, shouldPlay: Bool) async throws {
        guard let id else { return }
        guard shouldPlay else {
            audioController.pause()
            return
        }
        let list = fetchPlaylist(id: id)
        await audioController.add(audio: list, replace: true)
        audioController.togglePlay(id: list.first?.id, triggerPlay: true)
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
    
    @MainActor
    func play(with data: NetworkCodableDataType) async throws {
        let request = AudioPlayRequest.decodeData(of: data.data)
        try await play(id: request?.id, shouldPlay: request?.shouldPlay ?? false)
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
