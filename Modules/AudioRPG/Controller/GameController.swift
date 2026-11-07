// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

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

    // A playlist is not one unit on the wire. Every track is an item with a file of its own and
    // is sent, reported and acknowledged on its own: a playlist of many files cannot travel as
    // one package (SharePlay uploads one file per Journal slot). A report names the item that
    // was received, never the tracks of its playlist.

    /// The items a playlist needs on a device before it can start: the item itself and its first
    /// track (the same item for a track that is its own playlist's first). Every other track is
    /// sent ahead while the one before it plays.
    @MainActor func startItemIds(for id: UUID) -> [UUID] {
        guard let firstTrackId = fetchPlaylist(id: id).first?.id, firstTrackId != id else { return [id] }
        return [id, firstTrackId]
    }

    @MainActor func isPlaylist(id: UUID) -> Bool {
        gameItem(for: id).fileUrl == nil
    }

    @MainActor func allPlayersReported(for id: UUID) -> Bool {
        missingPlayers(for: id).isEmpty
    }

    @MainActor func missingPlayers(for itemId: UUID) -> [UUID] {
        Set(startItemIds(for: itemId).flatMap { missingPlayers(ofItem: $0) }).sorted()
    }

    @MainActor func missingPlayers(ofItem itemId: UUID) -> [UUID] {
        let reported = Set(gameModel.playerReport(for: itemId))
        return Set(gameModel.currentPlayers).subtracting(reported).sorted()
    }

    @MainActor func isAudioAvailable(itemId: UUID, for playerId: UUID) -> Bool {
        startItemIds(for: itemId).allSatisfy { gameModel.playerReport(for: $0).contains(playerId) }
    }

    @MainActor func requiredItemIds(for data: NetworkCodableDataType) -> [UUID] {
        guard let request = AudioPlayRequest.decodeData(of: data.data), request.shouldPlay else { return [] }
        var ids = startItemIds(for: request.id)
        if let trackId = request.trackId,
           !ids.contains(trackId),
           fetchPlaylist(id: request.id).contains(where: { $0.id == trackId }) {
            ids.append(trackId)
        }
        return ids
    }

    @MainActor func nextTrackId(after trackId: UUID, in rootId: UUID) -> UUID? {
        let ids = fetchPlaylist(id: rootId).map(\.id)
        guard let index = ids.firstIndex(of: trackId), ids.indices.contains(index + 1) else { return nil }
        return ids[index + 1]
    }

    /// The players a share of `itemId` lists. A player counts as reported once they have what the
    /// playlist needs to start (see `missingPlayers(for:)`).
    @MainActor func playerReportStatuses(for itemId: UUID, controls: [SharingControlModel]) -> [PlayerReportStatus] {
        let missing = Set(missingPlayers(for: itemId))
        return controls.playerReportStatuses { !missing.contains($0) }
    }

    @MainActor func report(itemId: UUID, for player: UUID) {
        guard !gameModel.playerReport(for: itemId).contains(player) else { return }
        gameModel.setPlayerReport(playerId: player, for: itemId)
    }
}

extension GameController {
    @MainActor
    func hasLocalDatabaseAudioData(for itemId: UUID) async -> Bool {
        guard let item = itemController.itemSync(for: itemId, noGame: true) else { return false }
        guard let fileUrl = item.fileUrl,
              let fileUrlDataController = itemController.fileUrlDataController
        else { return true }
        // A scan over the whole library: it must not ask iCloud to download every evicted file.
        // See CODE_AUDIT_Audio2 §7.1.
        return await fileUrlDataController.hasDownloadedDataWithoutFetching(for: fileUrl)
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

    /// The one playlist definition of an item: its own file, then the playlists of its entries.
    /// `depth` stops a folder cycle that the seen set does not catch, as every other tree walk
    /// does (`FolderTreeDepthLimit`). See CODE_AUDIT_Audio2 §5.15.
    @MainActor
    private func fetchPlaylist(id: UUID, seenIds: inout Set<UUID>, depth: Int = 0) -> [AudioModel] {
        guard depth < FolderTreeDepthLimit.max, !seenIds.contains(id) else { return [] }

        var list: [AudioModel] = []
        seenIds.insert(id)
        let item = gameItem(for: id)
        if item.fileUrl != nil {
            list.append(item)
        }
        item.entries.forEach {
            list.append(contentsOf: fetchPlaylist(id: $0.audioId, seenIds: &seenIds, depth: depth + 1))
        }
        return list
    }
}
