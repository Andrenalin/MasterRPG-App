// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - File Message Support

/// Why the master cannot serve a player's request for the bytes of an item. The request is
/// answered with `.failed` (never with silence): under request/answer a missing answer cannot
/// be told from a slow one, and the player would show a loading state for good. See
/// CODE_AUDIT_Game_Shareplay §5.5 and §5.1.
enum AssetRequestUnavailable: Error, Equatable {
    /// The master's file is an iCloud placeholder or was evicted.
    case notDownloaded
    /// The package does not fit one frame (`GameLimits.fitsOneMessage`); sending it would end
    /// the player's connection.
    case tooLarge(byteCount: Int)
}

extension MasterController {
    /// Shared "player acknowledged a reveal" bookkeeping of the file-backed modules (Pdf, Photo,
    /// Space), called by `handleFileBackedMessage` for the `.ok` of all three. See CODE_AUDIT_10 §9.2.
    ///
    /// Only the master collects the receipts. The one after which every player holds the
    /// item is announced with the authoritative list, so the share button of every player
    /// reads "everyone has it" as well.
    private func recordFileOkAck(
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

    /// The master's handler of every message of a file-backed module (Photo, Pdf, Space): a
    /// player's receipt, a request for the item's bytes, a player's report list and a player's
    /// contribution. `handleOtherUpdate` takes the module's own update subtypes (Space's
    /// transform). See CODE_AUDIT_Audio2 §9.4.
    func handleFileBackedMessage(
        _ model: GameNetworkModel,
        access: FileBackedModuleAccess,
        handleOtherUpdate: (GameNetworkModel) async -> Void = { _ in }
    ) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                controllable: access.controllable,
                setMasterVersion: access.setMasterVersion,
                markAvailable: access.markAvailable,
                announceList: { await broadcastFileList(access) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        if model.isAssetRequest {
            return try await answerAssetRequest(
                for: model,
                hasLocalFileData: { await access.controllable.hasLocalFileData(for: model.data.id) },
                package: { try await cachedPackage(module: model.data.type, itemId: model.data.id, controllable: access.controllable) }
            )
        }
        guard model.type == .update else { return nil }

        switch model.subType {
        case access.listSubType:
            guard await applyFileList(model, access: access) else { return nil }
            await broadcastFileList(access)
        case .generic:
            guard model.sender.role == .player,
                  access.isSharingEnabled(root.gameModel.gameControl.features)
            else { return nil }
            await showPlayerContribution(model, controllable: access.controllable)
        default:
            await handleOtherUpdate(model)
        }
        return nil
    }

    /// The answer to a player's request for the bytes of an item, shared by the file-backed
    /// modules and Audio. An iCloud file that has not downloaded cannot be exported: the requester
    /// is told, see `AssetRequestUnavailable`. Otherwise `package` supplies the bytes from the
    /// package cache, so N requests cost one export. See CODE_AUDIT_Game_Photo_Audio §9.1.
    func answerAssetRequest(
        for model: GameNetworkModel,
        hasLocalFileData: () async -> Bool,
        package: () async throws -> NetworkCodableDataType
    ) async throws -> NetworkCodableDataType {
        guard await hasLocalFileData() else {
            throw AssetRequestUnavailable.notDownloaded
        }
        return try await package()
    }

    /// Sends every player the authoritative report list: who has which version.
    func broadcastFileList(_ access: FileBackedModuleAccess) async {
        let list = await access.list(true, root.gameModel.gameConfig.id)
        await send(type: .update, subtype: access.listSubType, updated: list)
    }

    /// Applies a player's report list of a file-backed module.
    private func applyFileList(_ model: GameNetworkModel, access: FileBackedModuleAccess) async -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyList(access.module, from: model.sender.id, counter: model.counter),
              await access.applyList(model.data, model.sender.id, root.gameModel.gameConfig.id, false)
        else { return false }

        gameModel.recordList(access.module, counter: model.counter, from: model.sender.id)
        return true
    }

    /// A player shows a file-backed item to the group. The game master's copy is the one the
    /// group sees: the player names the item and sends its bytes only when the master has
    /// none, which the master then imports as its own. Either way the master shows the item
    /// like one of its own, so every player that lacks it is served the usual way.
    ///
    /// Not `private` because the Pdf, Photo, Space and Audio message files call it.
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
