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
import Combine
import DiceRPG
import TabletopKit
#endif

extension GameTableModel {
    // MARK: - Pin Thumbnails & Menu

    /// Loads the pin's photo thumbnail (2D pin pipeline) onto the 3D token.
    func loadPinThumbnail(pinId: UUID, photoId: UUID) async {
        defer {
            if pendingPinPhotoIds[pinId] == photoId {
                pendingPinPhotoIds[pinId] = nil
            }
            pendingThumbnailTasks[pinId] = nil
        }
        guard !Task.isCancelled, let cache = photoRoot.cacheControllable else { return }
        var image = await cache.thumbnail(for: photoId)
        if image == nil {
            guard let item = await photoRoot.itemControllable.item(for: photoId) else { return }
            await cache.thumbnailId(for: photoId, item: item)
            image = await cache.thumbnail(for: photoId)
        }
        guard !Task.isCancelled else { return }
        let currentPin = currentMapModel().flatMap { mapModel in
            pinId == mapModel.pointer.id
                ? mapModel.pointer
                : mapModel.mapPins.first(where: { $0.id == pinId })
        }
        guard currentPin?.photoId == photoId,
              let image,
              let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
        pawn.setPhotoTexture(image)
        pawn.loadedPhotoId = photoId
    }

    func beginPinPhotoLoad(pinId: UUID, photoId: UUID) -> Bool {
        guard pendingPinPhotoIds[pinId] != photoId else { return false }
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

    /// Registers the SwiftUI attachment used for the game-master pin menu.
    /// It remains parented to the table root rather than the pawn so pin size
    /// and zoom transforms never scale the controls.
    ///
    /// Discards any previously registered attachment first: `renderer.root`
    /// outlives one `RealityView` mount (see `GameTableView.initializeGameIfNeeded()`'s
    /// "if let game" branch), but the `Attachment(id: "pin-menu")` view given
    /// here does not — closing the volumetric window tears its `_HostingEntity`
    /// down. Without detaching the stale one before adopting the new one, both
    /// end up parented under `renderer.root` at once, and the next `content.add(
    /// renderer.root)` on reopen walks straight back over the old, mid-teardown
    /// entity — RealityKit aborts with `__CALLER_IS_PARENTING_AN_ENTITY_TO_AN_ENTITY_BEING_REMOVED__`.
    /// See `detachPinMenuAttachment()`, called from `GameTableView`'s
    /// `.onDisappear`, which is the other half of this same fix — that one
    /// covers the disappear side, this one is a belt-and-suspenders guard for
    /// any path that re-registers without having gone through it.
    func registerPinMenuAttachment(_ attachment: Entity) {
        if let previous = pinMenuAttachment, previous !== attachment {
            previous.removeFromParent()
        }
        pinMenuAttachment = attachment
        attachment.components.set(BillboardComponent())
        if attachment.parent == nil {
            renderer.root.addChild(attachment)
        }
        updatePinMenuAttachmentPosition()
    }

    /// Detaches the pin-menu SwiftUI attachment from the persisted table root
    /// before its owning `RealityView`/window tears down — see
    /// `registerPinMenuAttachment(_:)`'s doc for why leaving it parented past
    /// that point crashes the *next* time the window opens, not this one.
    func detachPinMenuAttachment() {
        pinMenuAttachment?.removeFromParent()
        pinMenuAttachment = nil
    }
}

#endif
