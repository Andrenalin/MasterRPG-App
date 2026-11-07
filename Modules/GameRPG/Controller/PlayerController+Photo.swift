// @copyright André Trettin

import CoreRPG
import Foundation
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

        return try await handleFileBackedMessage(
            model,
            access: root.photoRoot.fileBackedAccess,
            didReveal: { presentPhoto(itemId: $0) },
            didHold: { itemId in
                gameModel.removeRequestedPinPhotoId(itemId)
                // The game master may already show this photo full screen from a pin.
                applyWaitingMapPhoto(itemId: itemId)
            },
            handleOtherUpdate: { model in
                if model.data.data != nil {
                    try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                }
                if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    presentPhoto(itemId: model.data.id)
                }
            }
        )
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
}
