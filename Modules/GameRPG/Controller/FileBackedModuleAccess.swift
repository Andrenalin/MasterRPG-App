// @copyright André Trettin

import CoreRPG
import Foundation
import PdfRPG
import PhotoRPG
import SpaceRPG

/// What the game controllers need of a file-backed module (Photo, Pdf, Space): its report list,
/// its master-version baseline and its availability reports, behind one shape instead of three
/// per-module copies of every handler. Audio keeps its own handlers (pending plays), but shares
/// the sequencing keys and the answer to an asset request (`answerAssetRequest`). See CODE_AUDIT_Audio2 §9.4.
@MainActor
struct FileBackedModuleAccess {
    /// The module's key in the list sequence tracker.
    let module: NetworkModules
    /// The message subtype that carries the module's report list.
    let listSubType: RPGMessageActionType
    let controllable: any GameControllable
    /// Whether the module's sharing is on; modules without a feature flag are always on.
    let isSharingEnabled: (GameFeatureModel) -> Bool
    let setMasterVersion: (_ itemId: UUID, _ version: Int, _ masterId: UUID) -> Void
    let masterVersion: (_ itemId: UUID, _ masterId: UUID) -> Int?
    let markAvailable: (_ itemId: UUID, _ version: Int, _ playerIds: [UUID], _ masterId: UUID) -> Void
    let isAvailable: (_ itemId: UUID, _ playerId: UUID, _ masterId: UUID) -> Bool
    let list: (_ allPlayers: Bool, _ masterId: UUID) async -> NetworkCodableDataType
    let applyList: (
        _ data: NetworkCodableDataType,
        _ playerId: UUID,
        _ masterId: UUID,
        _ authoritative: Bool
    ) async -> Bool

    /// The access of the module an item type belongs to; `nil` for modules that are not
    /// file-backed this way.
    static func access(for type: NetworkModules, in root: GameRoot) -> FileBackedModuleAccess? {
        switch type {
        case .photo: root.photoRoot.fileBackedAccess
        case .pdf: root.pdfRoot.fileBackedAccess
        case .space: root.spaceRoot.fileBackedAccess
        default: nil
        }
    }

    /// The file-backed modules, in routing order.
    static func all(in root: GameRoot) -> [FileBackedModuleAccess] {
        [root.photoRoot.fileBackedAccess, root.pdfRoot.fileBackedAccess, root.spaceRoot.fileBackedAccess]
    }

    /// The access whose list is carried by `subType`.
    static func access(forListSubType subType: RPGMessageActionType, in root: GameRoot) -> FileBackedModuleAccess? {
        all(in: root).first { $0.listSubType == subType }
    }
}

@MainActor
extension PhotoRootModel {
    var fileBackedAccess: FileBackedModuleAccess {
        let photo = photoGameControllable
        return FileBackedModuleAccess(
            module: .photo,
            listSubType: .photoList,
            controllable: gameControllable,
            isSharingEnabled: \.photoSharing,
            setMasterVersion: { photo.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
            masterVersion: { photo.masterVersion(for: $0, masterId: $1) },
            markAvailable: { photo.markPhotoAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
            isAvailable: { photo.isPhotoAvailable(itemId: $0, for: $1, masterId: $2) },
            list: { await photo.photoList(allPlayers: $0, with: $1) },
            applyList: { await photo.applyPhotoList(data: $0, for: $1, with: $2, authoritative: $3) }
        )
    }
}

@MainActor
extension PdfRootModel {
    var fileBackedAccess: FileBackedModuleAccess {
        let pdf = pdfGameControllable
        return FileBackedModuleAccess(
            module: .pdf,
            listSubType: .pdfList,
            controllable: gameControllable,
            isSharingEnabled: { _ in true },
            setMasterVersion: { pdf.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
            masterVersion: { pdf.masterVersion(for: $0, masterId: $1) },
            markAvailable: { pdf.markPdfAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
            isAvailable: { pdf.isPdfAvailable(itemId: $0, for: $1, masterId: $2) },
            list: { await pdf.pdfList(allPlayers: $0, with: $1) },
            applyList: { await pdf.applyPdfList(data: $0, for: $1, with: $2, authoritative: $3) }
        )
    }
}

@MainActor
extension SpaceRootModel {
    var fileBackedAccess: FileBackedModuleAccess {
        let space = spaceGameControllable
        return FileBackedModuleAccess(
            module: .space,
            listSubType: .spaceList,
            controllable: gameControllable,
            isSharingEnabled: \.spaceSharing,
            setMasterVersion: { space.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
            masterVersion: { space.masterVersion(for: $0, masterId: $1) },
            markAvailable: { space.markSpaceAvailable(itemId: $0, version: $1, for: $2, masterId: $3) },
            isAvailable: { space.isSpaceAvailable(itemId: $0, for: $1, masterId: $2) },
            list: { await space.spaceList(allPlayers: $0, with: $1) },
            applyList: { await space.applySpaceList(data: $0, for: $1, with: $2, authoritative: $3) }
        )
    }
}
