// @copyright André Trettin

import CoreRPG
import Foundation

public protocol PhotoGameControllable: Sendable {
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
    /// The photo a show-photo event presented, `nil` until one arrives. See `PhotoGamePresentationModel`.
    @MainActor var presentedPhotoId: UUID? { get }
    @MainActor func presentPhoto(itemId: UUID)
}

/// Default implementations forwarding to `FileVersionGameControllable` —
/// PhotoRPG previously hand-duplicated all of this (`PhotoGameModel`, and
/// every method below) verbatim from PdfRPG/SpaceRPG's own identically-shaped
/// copies, differing only in type/method names. See CODE_AUDIT_10 §9.2.
@MainActor
public extension PhotoGameControllable where Self: FileVersionGameControllable, ListRequest == PhotoListRequest {
    func photoList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        await fileList(allPlayers: allPlayers, with: masterId)
    }

    @discardableResult
    func applyPhotoList(data: NetworkCodableDataType, for playerId: UUID, with masterId: UUID, authoritative: Bool) async -> Bool {
        await applyFileList(data: data, for: playerId, with: masterId, authoritative: authoritative)
    }

    func isPhotoAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        isFileAvailable(itemId: itemId, for: playerId, masterId: masterId)
    }

    func markPhotoAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        markFileAvailable(itemId: itemId, version: version, for: playerIds, masterId: masterId)
    }

    func markPhotoAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID) {
        markFileAvailableToCurrentPlayers(itemId: itemId, version: version, masterId: masterId)
    }

    func removePhotoReports(for playerId: UUID) {
        removeFileReports(for: playerId)
    }
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.versionLedger = PlayerVersionLedger()
        self.presentationModel = PhotoGamePresentationModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let versionLedger: PlayerVersionLedger
    let presentationModel: PhotoGamePresentationModel
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        versionLedger.reset()
        presentationModel.reset()
    }
}

extension GameController: FileVersionGameControllable {
    typealias ListRequest = PhotoListRequest
    static var fileModuleType: NetworkModules { .photo }
}

extension GameController: PhotoGameControllable {
    @MainActor var presentedPhotoId: UUID? { presentationModel.presentedItemId }

    @MainActor func presentPhoto(itemId: UUID) {
        presentationModel.present(itemId: itemId)
    }
}

public struct PhotoListRequest: FileListRequest {
    public let list: [UUID: Int]
    public let players: [UUID: [UUID: Int]]

    public init(list: [UUID: Int], players: [UUID: [UUID: Int]]) {
        self.list = list
        self.players = players
    }
}
