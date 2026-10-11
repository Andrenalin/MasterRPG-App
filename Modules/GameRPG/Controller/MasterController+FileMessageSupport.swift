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
    /// Only the master collects the receipts. The one after which every player holds the
    /// item is announced with the authoritative list, so the share button of every player
    /// reads "everyone has it" as well.
    ///
    /// Not `private` because it is called from `MasterController+PdfMessages.swift`,
    /// `MasterController+PhotoMessages.swift`, and `MasterController+SpaceMessages.swift`
    /// — three different files.
    func recordFileOkAck(
        _ model: GameNetworkModel,
        controllable: any GameControllable,
        setMasterVersion: (_ itemId: UUID, _ version: Int, _ masterId: UUID) -> Void,
        markAvailable: (_ itemId: UUID, _ version: Int, _ playerIds: [UUID], _ masterId: UUID) -> Void,
        announceList: () async -> Void
    ) async {
        let masterId = root.gameModel.gameConfig.id
        let baseline = await controllable.networkVersion(for: model.data.id)
        let wasComplete = controllable.allPlayersReported(for: model.data.id)
        setMasterVersion(model.data.id, baseline, masterId)
        markAvailable(model.data.id, model.data.effectiveAssetVersion, [model.sender.id], masterId)
        if !wasComplete, controllable.allPlayersReported(for: model.data.id) {
            await announceList()
        }
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

    /// A player shows a file-backed item to the group. The game master's copy is the one the
    /// group sees: the player names the item and sends its bytes only when the master has
    /// none, which the master then imports as its own. Either way the master shows the item
    /// like one of its own, so every player that lacks it is served the usual way.
    ///
    /// Not `private` because the Pdf, Photo and Space message files call it.
    func showPlayerContribution(
        _ model: GameNetworkModel,
        controllable: any GameControllable
    ) async {
        if await controllable.itemControllable.item(for: model.data.id) == nil {
            guard model.data.data != nil else { return }
            do {
                // No import policy for the player's package: accepted, see `updateGame(data:hide:deep:)`
                // (CODE_AUDIT_Folder §6.1, won't fix).
                try await controllable.updateGame(data: model.data, hide: false, deep: false)
            } catch {
                Logger.networking.error("MasterController: Failed to import shared \(model.data.type.token, privacy: .public) \(model.data.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return
            }
        }
        await show(for: await controllable.share(id: model.data.id))
    }
}
