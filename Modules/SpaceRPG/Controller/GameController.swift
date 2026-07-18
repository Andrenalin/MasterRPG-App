// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class SpaceGameModel: Sendable {
    init() {}

    var openSpace: Bool = false

    /// Reported file versions keyed by Space and participant. The game master's
    /// entry is the canonical baseline for availability decisions.
    var playerVersions: [UUID: [UUID: Int]] = [:]

    /// Latest master-sequenced placement for each Space and asset version. A
    /// delayed transform for an older file must not replace the retained pose
    /// of the version that is currently being presented.
    var transformStates: [UUID: [Int: SpaceTransformState]] = [:]

    func replaceVersions(with versions: [UUID: [UUID: Int]]) {
        playerVersions = versions
    }

    func applyVersions(_ versions: [UUID: Int], for playerId: UUID) {
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
        applyVersions([:], for: playerId)
    }

    func version(for itemId: UUID, playerId: UUID) -> Int? {
        playerVersions[itemId]?[playerId]
    }

    @discardableResult
    func applyTransform(
        itemId: UUID,
        version: Int,
        counter: Int,
        transform: SpaceTransformModel
    ) -> Bool {
        guard counter >= 0 else { return false }
        if let current = transformStates[itemId]?[version] {
            if counter == 0 {
                guard current.counter == 0 else { return false }
            } else {
                guard counter > current.counter else { return false }
            }
        }
        transformStates[itemId, default: [:]][version] = SpaceTransformState(
            version: version,
            counter: counter,
            transform: transform
        )
        return true
    }

    func transform(for itemId: UUID, version: Int) -> SpaceTransformModel? {
        transformState(for: itemId, version: version)?.transform
    }

    func transformState(for itemId: UUID, version: Int) -> SpaceTransformState? {
        guard let versions = transformStates[itemId] else { return nil }
        if version == 0 {
            return versions.values.max { $0.counter < $1.counter }
        }
        return versions[version] ?? versions[0]
    }

    func removeTransforms(for itemId: UUID, exceptVersion version: Int) {
        guard var versions = transformStates[itemId] else { return }
        versions = versions.filter { $0.key == 0 || $0.key == version }
        transformStates[itemId] = versions.isEmpty ? nil : versions
    }

    func resetTransforms() {
        transformStates.removeAll()
    }

    func reset() {
        openSpace = false
        playerVersions.removeAll()
        resetTransforms()
    }
}

struct SpaceTransformState: Equatable, Sendable {
    let version: Int
    let counter: Int
    let transform: SpaceTransformModel
}

public protocol SpaceGameControllable: Sendable {
    @MainActor func spaceList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @discardableResult
    @MainActor func applySpaceList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool
    @MainActor func masterVersion(for itemId: UUID, masterId: UUID) -> Int?
    @MainActor func reportedVersion(for itemId: UUID, playerId: UUID) -> Int?
    @MainActor func setMasterVersion(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func isSpaceAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool
    @MainActor func markSpaceAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID)
    @MainActor func markSpaceAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func removeSpaceReports(for playerId: UUID)

    @MainActor func isValidSpaceTransform(_ data: NetworkCodableDataType) -> Bool
    @discardableResult
    @MainActor func applySpaceTransform(data: NetworkCodableDataType, counter: Int) -> Bool
    @MainActor func latestSpaceTransform(for itemId: UUID, version: Int) -> NetworkCodableDataType?
    @MainActor func resetSpaceTransforms()
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.spaceGameModel = SpaceGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let spaceGameModel: SpaceGameModel

    @MainActor func gameItem(for itemId: UUID) -> SpaceModel {
        (gameModel.itemData[itemId] as? SpaceModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> SpaceModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        spaceGameModel.reset()
    }
}

extension GameController: SpaceGameControllable {
    @MainActor
    func spaceList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let localVersions = await localSpaceVersions()
        let request: SpaceListRequest
        if allPlayers {
            spaceGameModel.applyVersions(localVersions, for: masterId)
            rebuildPlayerReports(masterVersions: localVersions, masterId: masterId)
            request = SpaceListRequest(list: localVersions, players: spaceGameModel.playerVersions)
        } else {
            request = SpaceListRequest(list: localVersions, players: [:])
        }
        return NetworkCodableDataType(id: UUID(), type: .space, version: 0, data: request.encodeData())
    }

    @MainActor
    @discardableResult
    func applySpaceList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        guard let request = SpaceListRequest.decodeData(of: data.data) else { return false }

        if authoritative {
            var versions = request.players
            for (itemId, version) in request.list {
                versions[itemId, default: [:]][masterId] = version
            }
            spaceGameModel.replaceVersions(with: versions)
            rebuildPlayerReports(masterVersions: request.list, masterId: masterId)
        } else {
            let masterVersions = await localSpaceVersions()
            spaceGameModel.applyVersions(masterVersions, for: masterId)
            spaceGameModel.applyVersions(request.list, for: playerId)
            rebuildPlayerReports(masterVersions: masterVersions, masterId: masterId)
        }
        return true
    }

    @MainActor
    func masterVersion(for itemId: UUID, masterId: UUID) -> Int? {
        spaceGameModel.version(for: itemId, playerId: masterId)
    }

    @MainActor
    func reportedVersion(for itemId: UUID, playerId: UUID) -> Int? {
        spaceGameModel.version(for: itemId, playerId: playerId)
    }

    @MainActor
    func setMasterVersion(itemId: UUID, version: Int, masterId: UUID) {
        spaceGameModel.removeTransforms(for: itemId, exceptVersion: version)
        spaceGameModel.playerVersions[itemId, default: [:]][masterId] = version
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func isSpaceAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        guard let baseline = masterVersion(for: itemId, masterId: masterId) else { return false }
        return reportedVersion(for: itemId, playerId: playerId) == baseline
    }

    @MainActor
    func markSpaceAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        guard masterVersion(for: itemId, masterId: masterId) == version else { return }
        for playerId in playerIds {
            spaceGameModel.playerVersions[itemId, default: [:]][playerId] = version
        }
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func markSpaceAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID) {
        let players = Set(gameModel.currentPlayers).union([masterId])
        markSpaceAvailable(itemId: itemId, version: version, for: Array(players), masterId: masterId)
    }

    @MainActor
    func removeSpaceReports(for playerId: UUID) {
        spaceGameModel.remove(playerId: playerId)
        gameModel.removePlayerReport(for: playerId)
    }

    @MainActor
    func isValidSpaceTransform(_ data: NetworkCodableDataType) -> Bool {
        data.type == .space && SpaceTransformModel.decodeData(of: data.data) != nil
    }

    @MainActor
    @discardableResult
    func applySpaceTransform(data: NetworkCodableDataType, counter: Int) -> Bool {
        guard data.type == .space,
              let transform = SpaceTransformModel.decodeData(of: data.data)
        else { return false }
        return spaceGameModel.applyTransform(
            itemId: data.id,
            version: data.effectiveAssetVersion,
            counter: counter,
            transform: transform
        )
    }

    @MainActor
    func latestSpaceTransform(for itemId: UUID, version: Int) -> NetworkCodableDataType? {
        guard let state = spaceGameModel.transformState(for: itemId, version: version),
              let data = state.transform.encodeData()
        else { return nil }
        return NetworkCodableDataType(
            id: itemId,
            type: .space,
            version: state.version,
            data: data
        )
    }

    @MainActor
    func resetSpaceTransforms() {
        spaceGameModel.resetTransforms()
    }

    func updateGame(data: NetworkCodableDataType, subtype: RPGMessageActionType) async throws {
        guard subtype == .spaceTransform else { return }
        _ = await applySpaceTransform(data: data, counter: 0)
    }

    @MainActor
    private func localSpaceVersions() async -> [UUID: Int] {
        var versions: [UUID: Int] = [:]
        for itemId in itemController.itemDataModel.items {
            guard await hasLocalDatabaseSpaceData(for: itemId) else { continue }
            versions[itemId] = await networkVersion(for: itemId)
        }
        return versions
    }

    @MainActor
    private func hasLocalDatabaseSpaceData(for itemId: UUID) async -> Bool {
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
                .union(spaceGameModel.playerVersions.keys)
                .union(gameModel.playerReports.keys)
        }

        for itemId in itemIds {
            guard let baseline = masterVersions[itemId] ?? spaceGameModel.version(for: itemId, playerId: masterId) else {
                gameModel.playerReports[itemId] = []
                continue
            }
            spaceGameModel.removeTransforms(for: itemId, exceptVersion: baseline)
            gameModel.playerReports[itemId] = (spaceGameModel.playerVersions[itemId] ?? [:])
                .compactMap { playerId, version in version == baseline ? playerId : nil }
                .sorted()
        }
    }
}

struct SpaceListRequest: Codable, Sendable, Equatable {
    let list: [UUID: Int]
    let players: [UUID: [UUID: Int]]
}

extension SpaceListRequest {
    static func decodeData(of data: Data?) -> SpaceListRequest? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SpaceListRequest.self, from: data)
    }

    func encodeData() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
