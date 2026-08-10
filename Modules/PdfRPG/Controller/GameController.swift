// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class PdfGameModel: Sendable {
    init() {}

    /// Reported file versions keyed by PDF and participant. The game master's
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

public protocol PdfGameControllable: Sendable {
    @MainActor func pdfList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @discardableResult
    @MainActor func applyPdfList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool
    @MainActor func masterVersion(for itemId: UUID, masterId: UUID) -> Int?
    @MainActor func reportedVersion(for itemId: UUID, playerId: UUID) -> Int?
    @MainActor func setMasterVersion(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func isPdfAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool
    @MainActor func markPdfAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID)
    @MainActor func markPdfAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func removePdfReports(for playerId: UUID)
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.pdfGameModel = PdfGameModel()
    }
    
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let pdfGameModel: PdfGameModel
    
    @MainActor func gameItem(for itemId: UUID) -> PdfModel {
        (gameModel.itemData[itemId] as? PdfModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> PdfModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        pdfGameModel.reset()
    }
}

extension GameController: PdfGameControllable {
    @MainActor
    func pdfList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let localVersions = await localPdfVersions()
        let request: PdfListRequest
        if allPlayers {
            pdfGameModel.apply(localVersions, for: masterId)
            rebuildPlayerReports(masterVersions: localVersions, masterId: masterId)
            request = PdfListRequest(list: localVersions, players: pdfGameModel.playerVersions)
        } else {
            request = PdfListRequest(list: localVersions, players: [:])
        }
        return NetworkCodableDataType(id: UUID(), type: .pdf, version: 0, data: request.encodeData())
    }

    @MainActor
    @discardableResult
    func applyPdfList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        guard let request = PdfListRequest.decodeData(of: data.data) else { return false }

        if authoritative {
            var versions = request.players
            for (itemId, version) in request.list {
                versions[itemId, default: [:]][masterId] = version
            }
            pdfGameModel.replace(with: versions)
            rebuildPlayerReports(masterVersions: request.list, masterId: masterId)
        } else {
            let masterVersions = await localPdfVersions()
            pdfGameModel.apply(masterVersions, for: masterId)
            pdfGameModel.apply(request.list, for: playerId)
            rebuildPlayerReports(masterVersions: masterVersions, masterId: masterId)
        }
        return true
    }

    @MainActor
    func masterVersion(for itemId: UUID, masterId: UUID) -> Int? {
        pdfGameModel.version(for: itemId, playerId: masterId)
    }

    @MainActor
    func reportedVersion(for itemId: UUID, playerId: UUID) -> Int? {
        pdfGameModel.version(for: itemId, playerId: playerId)
    }

    @MainActor
    func setMasterVersion(itemId: UUID, version: Int, masterId: UUID) {
        pdfGameModel.playerVersions[itemId, default: [:]][masterId] = version
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func isPdfAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        guard let baseline = masterVersion(for: itemId, masterId: masterId) else { return false }
        return pdfGameModel.version(for: itemId, playerId: playerId) == baseline
    }

    @MainActor
    func markPdfAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        guard masterVersion(for: itemId, masterId: masterId) == version else { return }
        for playerId in playerIds {
            pdfGameModel.playerVersions[itemId, default: [:]][playerId] = version
        }
        rebuildPlayerReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func markPdfAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID) {
        let players = Set(gameModel.currentPlayers).union([masterId])
        markPdfAvailable(itemId: itemId, version: version, for: Array(players), masterId: masterId)
    }

    @MainActor
    func removePdfReports(for playerId: UUID) {
        pdfGameModel.remove(playerId: playerId)
        gameModel.removePlayerReport(for: playerId)
    }

    @MainActor
    private func localPdfVersions() async -> [UUID: Int] {
        var versions: [UUID: Int] = [:]
        for itemId in itemController.itemDataModel.items {
            guard await hasLocalDatabasePdfData(for: itemId) else { continue }
            versions[itemId] = await networkVersion(for: itemId)
        }
        return versions
    }

    @MainActor
    private func hasLocalDatabasePdfData(for itemId: UUID) async -> Bool {
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
                .union(pdfGameModel.playerVersions.keys)
                .union(gameModel.playerReports.keys)
        }

        for itemId in itemIds {
            guard let baseline = masterVersions[itemId] ?? pdfGameModel.version(for: itemId, playerId: masterId) else {
                gameModel.playerReports[itemId] = []
                continue
            }
            gameModel.playerReports[itemId] = (pdfGameModel.playerVersions[itemId] ?? [:])
                .compactMap { playerId, version in version == baseline ? playerId : nil }
                .sorted()
        }
    }
}

struct PdfListRequest: Codable, Sendable, Equatable, MessageMapper {
    let list: [UUID: Int]
    let players: [UUID: [UUID: Int]]
}
