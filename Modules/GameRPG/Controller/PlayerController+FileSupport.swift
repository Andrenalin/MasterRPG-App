// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - File Message Support

extension PlayerController {
    /// The player's handler of every master message of a file-backed module (Photo, Pdf,
    /// Space). The caller has already refused acknowledgements and non-master senders.
    /// The module-specific parts are hooks: `didReveal` and `didHold` run once the item is
    /// readable here, `handleOtherUpdate` takes the update subtypes besides the report list,
    /// and `versionlessSubTypes` are the updates that name no item version. See
    /// CODE_AUDIT_Audio2 §9.4.
    func handleFileBackedMessage(
        _ model: GameNetworkModel,
        access: FileBackedModuleAccess,
        versionlessSubTypes: Set<RPGMessageActionType> = [],
        didReveal: (UUID) -> Void = { _ in },
        didHold: (UUID) -> Void = { _ in },
        handleOtherUpdate: (GameNetworkModel) async throws -> Void = { _ in }
    ) async throws -> GameNetworkModel? {
        let masterId = model.masterId
        let localPlayerId = root.gameModel.gameConfig.id
        let isList = model.type == .update && model.subType == access.listSubType
        if !isList, !(model.type == .update && versionlessSubTypes.contains(model.subType)) {
            access.setMasterVersion(model.data.id, model.data.effectiveAssetVersion, masterId)
        }

        switch model.type {
        case .reveal:
            guard try await access.controllable.reveal(itemId: model.data.id, data: model.data, save: true) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            didReveal(model.data.id)
            access.markAvailable(model.data.id, model.data.effectiveAssetVersion, [localPlayerId, masterId], masterId)
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            if model.data.data != nil {
                try await access.controllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            }
            guard await holdsFile(of: model.data, in: access.controllable) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            access.markAvailable(model.data.id, model.data.effectiveAssetVersion, [localPlayerId], masterId)
            didHold(model.data.id)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            if isList {
                _ = await applyFileList(model, access: access)
            } else {
                try await handleOtherUpdate(model)
            }
            return nil
        }
    }

    /// Whether this device holds the named item in the named version with its file readable.
    /// A store names an item or carries it; this is what decides between `.ok` and a request.
    func holdsFile(of data: NetworkCodableDataType, in controllable: any GameControllable) async -> Bool {
        guard await controllable.hasItem(id: data.id, version: data.version) else { return false }
        return await controllable.hasLocalFileData(for: data.id)
    }

    private func applyFileList(_ model: GameNetworkModel, access: FileBackedModuleAccess) async -> Bool {
        guard gameModel.canApplyList(access.module, from: model.masterId, counter: model.counter),
              await access.applyList(model.data, model.masterId, model.masterId, true)
        else { return false }

        gameModel.recordList(access.module, counter: model.counter, from: model.masterId)
        return true
    }

    /// Reports what this device holds of a file-backed module to the game master.
    func sendFileList(_ access: FileBackedModuleAccess) async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard root.gameModel.gameType != .proxy else { return }
        let list = await access.list(false, root.gameModel.gameConfig.master.id)
        await send(type: .update, subType: access.listSubType, updated: list)
    }

    /// Reports what this device holds of Photo, Pdf and Space to the game master.
    func sendFileLists() async {
        for access in FileBackedModuleAccess.all(in: root) {
            await sendFileList(access)
        }
    }
}
