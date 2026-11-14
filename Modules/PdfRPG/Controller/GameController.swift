// @copyright André Trettin

import CoreRPG
import Foundation

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
    @MainActor func removePdfReports(for playerId: UUID)
}

/// Default implementations forwarding to `FileVersionGameControllable` —
/// PdfRPG previously hand-duplicated all of this (`PdfGameModel`, and every
/// method below) verbatim from PhotoRPG/SpaceRPG's own identically-shaped
/// copies, differing only in type/method names. See CODE_AUDIT_10 §9.2.
@MainActor
public extension PdfGameControllable where Self: FileVersionGameControllable, ListRequest == PdfListRequest {
    func pdfList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        await fileList(allPlayers: allPlayers, with: masterId)
    }

    @discardableResult
    func applyPdfList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        await applyFileList(data: data, for: playerId, with: masterId, authoritative: authoritative)
    }

    func isPdfAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        isFileAvailable(itemId: itemId, for: playerId, masterId: masterId)
    }

    func markPdfAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        markFileAvailable(itemId: itemId, version: version, for: playerIds, masterId: masterId)
    }

    func removePdfReports(for playerId: UUID) {
        removeFileReports(for: playerId)
    }
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.versionLedger = PlayerVersionLedger()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let versionLedger: PlayerVersionLedger
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        versionLedger.reset()
    }
}

extension GameController: FileVersionGameControllable {
    typealias ListRequest = PdfListRequest
    static var fileModuleType: NetworkModules { .pdf }
}

extension GameController: PdfGameControllable {}

public struct PdfListRequest: FileListRequest {
    public let list: [UUID: Int]
    public let players: [UUID: [UUID: Int]]

    public init(list: [UUID: Int], players: [UUID: [UUID: Int]]) {
        self.list = list
        self.players = players
    }
}
