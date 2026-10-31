// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import DiceRPG
import TabletopKit
#endif

extension GameTableModel {
    // MARK: - Pin Thumbnails & Menu

    /// Loads the pin's photo thumbnail (2D pin pipeline) onto the 3D token.
    func loadPinThumbnail(pinId: UUID, photoId: UUID) async {
        defer {
            // Only the load that is still current for this pin may clear its bookkeeping: a newer
            // load for a different photo has already replaced `pendingPinPhotoIds[pinId]` and
            // `pendingThumbnailTasks[pinId]`, and must keep both.
            if pendingPinPhotoIds[pinId] == photoId {
                pendingPinPhotoIds[pinId] = nil
                pendingThumbnailTasks[pinId] = nil
            }
        }
        guard !Task.isCancelled, let cache = photoRoot.cacheControllable else { return }
        var image = await cache.thumbnail(for: photoId)
        if image == nil {
            if let item = await photoRoot.itemControllable.item(for: photoId) {
                await cache.thumbnailId(for: photoId, item: item)
                image = await cache.thumbnail(for: photoId)
            }
        }
        guard !Task.isCancelled else { return }
        let currentPin = currentMapModel().flatMap { mapModel in
            pinId == mapModel.pointer.id
                ? mapModel.pointer
                : mapModel.mapPins.first(where: { $0.id == pinId })
        }
        guard currentPin?.photoId == photoId,
              let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
        guard let image else {
            // Don't retry on every map sync: wait until the pin's photo changes.
            failedPinPhotoIds[pinId] = photoId
            return
        }
        failedPinPhotoIds[pinId] = nil
        pawn.setPhotoTexture(image)
        pawn.loadedPhotoId = photoId
    }

    func beginPinPhotoLoad(pinId: UUID, photoId: UUID) -> Bool {
        guard pendingPinPhotoIds[pinId] != photoId,
              failedPinPhotoIds[pinId] != photoId else { return false }
        pendingPinPhotoIds[pinId] = photoId
        return true
    }

    /// Records the thumbnail-load `Task` spawned for `pinId`, cancelling any
    /// still-running load for that same pin it supersedes.
    func trackThumbnailTask(for pinId: UUID, _ task: Task<Void?, Never>) {
        pendingThumbnailTasks[pinId]?.cancel()
        pendingThumbnailTasks[pinId] = task
    }

    /// The master moves every pin. A player moves its own pin and may move the
    /// shared pointer while the game master has made that pointer visible,
    /// matching the existing 2D game-map contract.
    func canMovePin(_ pinId: UUID) -> Bool {
        guard let mapModel = currentMapModel() else { return false }
        if pinId == mapModel.pointer.id {
            return isGameMaster || mapModel.pointer.isShown
        }
        return isGameMaster || pinId == playerPinId
    }

    /// Registers the SwiftUI attachment used for the game-master pin menu. See
    /// `TablePopoverAnchor` for how it stands on the table and why a stale attachment is
    /// discarded first.
    func registerPinMenuAttachment(_ attachment: Entity) {
        pinMenuPopover.register(attachment, in: renderer.root)
        updatePinMenuAttachmentPosition()
    }

    /// The attachment view reports its own height, in meters, whenever its layout changes.
    func pinMenuAttachmentHeightChanged(_ height: Float) {
        pinMenuPopover.attachmentHeightChanged(height)
    }

    /// Detaches the pin-menu SwiftUI attachment from the persisted table root before its owning
    /// `RealityView`/window tears down — see `TablePopoverAnchor.detach()`.
    func detachPinMenuAttachment() {
        pinMenuPopover.detach()
    }
}

#endif
