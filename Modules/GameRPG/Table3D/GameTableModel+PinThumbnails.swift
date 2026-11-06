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

/// A failed pin photo load: the photo and the state of its item at that time. The item of a photo
/// a player has not received yet is missing or has no file, so a later arrival changes this value
/// and allows a retry, while an unchanged one is not retried on every map sync.
struct PinPhotoLoadAttempt: Equatable {
    let photoId: UUID
    let version: Int?
    let fileId: UUID?
    let contentHash: String?
    let hasInlineData: Bool
}

extension GameTableModel {
    // MARK: - Pin Thumbnails & Menu

    /// The current state of the photo item behind a pin's photo (game copy first, like `item(for:)`).
    func pinPhotoLoadAttempt(photoId: UUID) -> PinPhotoLoadAttempt {
        let photo = photoRoot.itemControllable.itemSync(for: photoId) as? PhotoModel
        return PinPhotoLoadAttempt(
            photoId: photoId,
            version: photo?.version,
            fileId: photo?.fileUrl?.fileId,
            contentHash: photo?.fileUrl?.contentHash,
            hasInlineData: photo?.fileUrl?.data != nil
        )
    }

    /// Records a failed load and re-syncs the pins as soon as the photo item changes, so a photo
    /// that reaches a player after the pin appeared is shown without leaving the 3D table.
    private func markPinPhotoFailed(pinId: UUID, photoId: UUID) {
        let attempt = pinPhotoLoadAttempt(photoId: photoId)
        failedPinPhotos[pinId] = attempt
        pinPhotoRetryTasks[pinId]?.cancel()
        pinPhotoRetryTasks[pinId] = Task { [weak self] in
            guard let changes = self?.photoItemChanges(photoId: photoId) else { return }
            for await current in changes where current != attempt {
                guard !Task.isCancelled else { return }
                self?.syncPawnsWithMapPins()
                return
            }
        }
    }

    private func photoItemChanges(photoId: UUID) -> some AsyncSequence<PinPhotoLoadAttempt, Never> {
        Observations { [weak self] in
            self?.pinPhotoLoadAttempt(photoId: photoId)
                ?? PinPhotoLoadAttempt(photoId: photoId, version: nil, fileId: nil, contentHash: nil, hasInlineData: false)
        }
    }

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
            markPinPhotoFailed(pinId: pinId, photoId: photoId)
            return
        }
        guard pawn.setPhotoTexture(image) else {
            // The texture could not be made from this thumbnail; retry only when the photo changes.
            markPinPhotoFailed(pinId: pinId, photoId: photoId)
            return
        }
        failedPinPhotos[pinId] = nil
        pinPhotoRetryTasks[pinId]?.cancel()
        pinPhotoRetryTasks[pinId] = nil
        pawn.loadedPhotoId = photoId
    }

    func beginPinPhotoLoad(pinId: UUID, photoId: UUID) -> Bool {
        guard pendingPinPhotoIds[pinId] != photoId,
              failedPinPhotos[pinId] != pinPhotoLoadAttempt(photoId: photoId) else { return false }
        pendingPinPhotoIds[pinId] = photoId
        return true
    }

    /// Records the thumbnail-load `Task` spawned for `pinId`, cancelling any
    /// still-running load for that same pin it supersedes.
    func trackThumbnailTask(for pinId: UUID, _ task: Task<Void?, Never>) {
        pendingThumbnailTasks[pinId]?.cancel()
        pendingThumbnailTasks[pinId] = task
    }

    /// The master moves every pin. A player moves its own pin and the player pins the game
    /// master gave this device (`MapPinModel.isControlled(by:)`, observers included), and may
    /// move the shared pointer while the game master has made that pointer visible, matching
    /// the existing 2D game-map contract.
    func canMovePin(_ pinId: UUID) -> Bool {
        guard let mapModel = currentMapModel() else { return false }
        if pinId == mapModel.pointer.id {
            return isGameMaster || mapModel.pointer.isShown
        }
        return isGameMaster
            || mapModel.mapPins.first(where: { $0.id == pinId })?.isControlled(by: playerPinId) == true
    }
}

#endif
