// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

// MARK: - File Message Support

extension MasterController {
    /// Shared "player acknowledged a reveal" bookkeeping for the three
    /// file-backed modules (Pdf, Photo, Space) — handlePdf/handlePhoto/
    /// handleSpace's `.ok` branch previously hand-duplicated this exact
    /// sequence, differing only in which module's accessors they called.
    /// See CODE_AUDIT_10 §9.2.
    ///
    /// Not `private` because it is called from `MasterController+PdfMessages.swift`,
    /// `MasterController+PhotoMessages.swift`, and `MasterController+SpaceMessages.swift`
    /// — three different files.
    func recordFileOkAck(
        _ model: GameNetworkModel,
        networkVersion: (_ itemId: UUID) async -> Int,
        setMasterVersion: (_ itemId: UUID, _ version: Int, _ masterId: UUID) -> Void,
        markAvailable: (_ itemId: UUID, _ version: Int, _ playerIds: [UUID], _ masterId: UUID) -> Void
    ) async {
        let masterId = root.gameModel.gameConfig.id
        let baseline = await networkVersion(model.data.id)
        setMasterVersion(model.data.id, baseline, masterId)
        markAvailable(model.data.id, model.data.effectiveAssetVersion, [model.sender.id], masterId)
    }

    /// Shared "apply an incoming file-version list" bookkeeping for the
    /// three file-backed modules — applyPdfList/applyPhotoList/
    /// applySpaceList below previously hand-duplicated this exact sequence,
    /// differing only in which module's accessors they called.
    /// See CODE_AUDIT_10 §9.2.
    ///
    /// Not `private` because it is called from `MasterController+PdfMessages.swift`,
    /// `MasterController+PhotoMessages.swift`, and `MasterController+SpaceMessages.swift`
    /// — three different files.
    func applyFileList(
        _ model: GameNetworkModel,
        canApply: (_ senderId: UUID, _ counter: Int) -> Bool,
        apply: (_ data: NetworkCodableDataType, _ senderId: UUID, _ masterId: UUID, _ authoritative: Bool) async -> Bool,
        record: (_ counter: Int, _ senderId: UUID) -> Void
    ) async -> Bool {
        guard !model.sender.isMaster,
              canApply(model.sender.id, model.counter),
              await apply(model.data, model.sender.id, root.gameModel.gameConfig.id, false)
        else { return false }

        record(model.counter, model.sender.id)
        return true
    }
}
