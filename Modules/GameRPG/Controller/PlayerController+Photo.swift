// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import PhotoRPG

extension PlayerController {
    func handlePhoto(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // Photos come from the game master only; a player shows one through the master.
        guard !model.isAcknowledgement, model.sender.isMaster else { return nil }
        if model.type == .update, model.subType == .photoPresentation {
            // Names no photo version: only how a photo over the map is shown.
            await handleMapPhotoPresentation(model)
            return nil
        }

        let masterId = model.masterId
        let localPlayerId = root.gameModel.gameConfig.id
        let photo = root.photoRoot.photoGameControllable
        if !(model.type == .update && model.subType == .photoList) {
            photo.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        switch model.type {
        case .reveal:
            guard try await root.photoRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            presentPhoto(itemId: model.data.id)
            photo.markPhotoAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId, masterId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            if model.data.data != nil {
                try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            }
            guard await holdsFile(of: model.data, in: root.photoRoot.gameControllable) else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            gameModel.removeRequestedPinPhotoId(model.data.id)
            photo.markPhotoAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [localPlayerId],
                masterId: masterId
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .photoList:
                _ = await applyPhotoList(model)
                return nil
            default:
                if model.data.data != nil {
                    try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                }
            }
            if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                presentPhoto(itemId: model.data.id)
            }
        }
        return nil
    }

    /// A show-photo event: switches the game screen to the photo and names it as the presented
    /// photo, which the visionOS 3D image viewer follows. A photo the game master showed while
    /// the map was on screen opens on the map instead (see `PlayerController+MapPhoto.swift`).
    /// A `.store` only caches its photo and never comes here.
    func presentPhoto(itemId: UUID) {
        guard !presentOnMap(.photo, itemId: itemId) else { return }
        gameModel.setGameUpdateType(.photo)
        root.photoRoot.photoGameControllable.presentPhoto(itemId: itemId)
    }

    /// Whether this device holds the named item in the named version with its file readable.
    /// A store names an item or carries it; this is what decides between `.ok` and a request.
    func holdsFile(of data: NetworkCodableDataType, in controllable: any GameControllable) async -> Bool {
        guard await controllable.hasItem(id: data.id, version: data.version) else { return false }
        return await controllable.hasLocalFileData(for: data.id)
    }

    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        guard gameModel.canApplyPhotoList(from: model.masterId, counter: model.counter),
              await root.photoRoot.photoGameControllable.applyPhotoList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordPhotoList(counter: model.counter, from: model.masterId)
        return true
    }

    func sendPhotoList() async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard root.gameModel.gameType != .proxy else { return }
        let photoList = await root.photoRoot.photoGameControllable.photoList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .photoList, updated: photoList)
    }
}
