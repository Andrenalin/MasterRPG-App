// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class PhotoGameModel: Sendable {
    init() {}

    /// Reported file versions keyed by photo and participant. The master's
    /// entry is the canonical baseline for every availability decision.
    var playerVersions: [UUID: [UUID: Int]] = [:]

    func replace(with versions: [UUID: [UUID: Int]]) {
        playerVersions = versions
    }

    func apply(_ versions: [UUID: Int], for playerId: UUID) {
        // Snapshot the keys before mutating the dictionary. Removing the last
        // participant can delete an item entry entirely.
        for itemId in Set(playerVersions.keys) {
            playerVersions[itemId]?[playerId] = nil
            if playerVersions[itemId]?.isEmpty == true {
                playerVersions[itemId] = nil
            }
        }
        for (itemId, version) in versions {
            playerVersions[itemId, default: [:]][playerId] = version
        }
    }

    func remove(playerId: UUID) {
        apply([:], for: playerId)
    }

    func version(for itemId: UUID, playerId: UUID) -> Int? {
        playerVersions[itemId]?[playerId]
    }

    func reset() {
        playerVersions.removeAll()
    }
}

public protocol PhotoGameControllable {
    @MainActor func photoList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @discardableResult
    @MainActor func applyPhotoList(data: NetworkCodableDataType, for playerId: UUID, with masterId: UUID, authoritative: Bool) async -> Bool
    @MainActor func masterVersion(for itemId: UUID, masterId: UUID) -> Int?
    @MainActor func reportedVersion(for itemId: UUID, playerId: UUID) -> Int?
    @MainActor func setMasterVersion(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func isPhotoAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool
    @MainActor func markPhotoAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID)
    @MainActor func markPhotoAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func removePhotoReports(for playerId: UUID)
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.photoGameModel = PhotoGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let photoGameModel: PhotoGameModel

    @MainActor func gameItem(for itemId: UUID) -> PhotoModel {
        (gameModel.itemData[itemId] as? PhotoModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> PhotoModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        photoGameModel.reset()
    }
}

extension GameController: PhotoGameControllable {
    @MainActor
    func photoList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let localVersions = await localPhotoVersions()
        let request: PhotoListRequest
        if allPlayers {
            photoGameModel.apply(localVersions, for: masterId)
            rebuildPlayerReports(masterVersions: localVersions, masterId: masterId)
            request = PhotoListRequest(list: localVersions, players: photoGameModel.playerVersions)
        } else {
            request = PhotoListRequest(list: localVersions, players: [:])
        }
        return NetworkCodableDataType(id: UUID(), type: .photo, version: 0, data: request.encodeData())
    }

    @MainActor
    @discardableResult
    func applyPhotoList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        guard let request = PhotoListRequest.decodeData(of: data.data) else { return false }

        if authoritative {
            var versions = request.players
            for (itemId, version) in request.list {
                versions[itemId, default: [:]][masterId] = version
            }
            photoGameModel.replace(with: versions)
            rebuildPlayerReports(masterVersions: request.list, masterId: masterId)
        } else {
            let masterVersions = await localPhotoVersions()
            photoGameModel.apply(masterVersions, for: masterId)
            photoGameModel.apply(request.list, for: playerId)
            rebuildPlayerReports(masterVersions: masterVersions, masterId: masterId)
        }
        return true
    }

    @MainActor
    func masterVersion(for itemId: UUID, masterId: UUID) -> Int? {
        photoGameModel.version(for: itemId, playerId: masterId)
    }

    @MainActor
    func reportedVersion(for itemId: UUID, playerId: UUID) -> Int? {
        photoGameModel.version(for: itemId, playerId: playerId)
    }

    @MainActor
    func setMasterVersion(itemId: UUID, version: Int, masterId: UUID) {
        photoGameModel.playerVersions[itemId, default: [:]][masterId] = version
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func isPhotoAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        guard let baseline = masterVersion(for: itemId, masterId: masterId) else { return false }
        return photoGameModel.version(for: itemId, playerId: playerId) == baseline
    }

    @MainActor
    func markPhotoAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        guard masterVersion(for: itemId, masterId: masterId) == version else { return }
        for playerId in playerIds {
            photoGameModel.playerVersions[itemId, default: [:]][playerId] = version
        }
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func markPhotoAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID) {
        let players = Set(gameModel.currentPlayers).union([masterId])
        markPhotoAvailable(itemId: itemId, version: version, for: Array(players), masterId: masterId)
    }

    @MainActor
    func removePhotoReports(for playerId: UUID) {
        photoGameModel.remove(playerId: playerId)
        gameModel.removePlayerReport(for: playerId)
    }

    @MainActor
    private func localPhotoVersions() async -> [UUID: Int] {
        var versions: [UUID: Int] = [:]
        for itemId in itemController.itemDataModel.items {
            guard await hasLocalDatabasePhotoData(for: itemId) else { continue }
            versions[itemId] = await networkVersion(for: itemId)
        }
        return versions
    }

    @MainActor
    private func hasLocalDatabasePhotoData(for itemId: UUID) async -> Bool {
        guard let item = itemController.itemSync(for: itemId, noGame: true) else { return false }
        guard let fileUrl = item.fileUrl else { return true }
        guard let fileUrlDataController = itemController.fileUrlDataController else { return false }
        return await fileUrlDataController.hasLocalData(for: fileUrl)
    }

    @MainActor
    private func rebuildPlayerReports(masterVersions: [UUID: Int], masterId: UUID, only itemId: UUID? = nil) {
        let itemIds: Set<UUID>
        if let itemId {
            itemIds = [itemId]
        } else {
            itemIds = Set(masterVersions.keys)
                .union(photoGameModel.playerVersions.keys)
                .union(gameModel.playerReports.keys)
        }

        for itemId in itemIds {
            guard let baseline = masterVersions[itemId] ?? photoGameModel.version(for: itemId, playerId: masterId) else {
                gameModel.playerReports[itemId] = []
                continue
            }
            gameModel.playerReports[itemId] = (photoGameModel.playerVersions[itemId] ?? [:])
                .compactMap { playerId, version in version == baseline ? playerId : nil }
                .sorted()
        }
    }
}

struct PhotoListRequest: Codable, Sendable, Equatable, MessageMapper {
    let list: [UUID: Int]
    let players: [UUID: [UUID: Int]]
}
