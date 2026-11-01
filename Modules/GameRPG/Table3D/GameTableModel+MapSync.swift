// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

extension GameTableModel {
    // MARK: - Map Sync & Fog of War

    /// Applies the current game map to the table and waits until the *newest* request has finished.
    /// A request superseded by a newer one is cancelled, so this keeps waiting for its successor
    /// instead of returning while the table still shows the previous map. The work belongs to the
    /// model, not the caller: cancelling the calling task does not cancel it.
    func handleMapChange(isGameMaster: Bool) async {
        var task = replaceMapChangeTask(isGameMaster: isGameMaster)
        await task.value
        while let newest = mapChangeTask, newest != task {
            task = newest
            await newest.value
        }
    }

    /// Re-renders the board's fog for a remote map update. Sets the role, then goes through the
    /// same cancel-then-replace choke point every other fog-affecting entry point uses.
    func refreshFogOfWar(isGameMaster: Bool) async {
        updateRole(isGameMaster)
        await replaceFogOfWarTask().value
    }

    /// Records the local role. Rendering (`renderIsGameMaster`) and every permission check read it.
    /// Returns whether it changed.
    @discardableResult
    func updateRole(_ isGameMaster: Bool) -> Bool {
        guard self.isGameMaster != isGameMaster else { return false }
        self.isGameMaster = isGameMaster
        fogSignature = nil
        return true
    }

    /// Cancels any in-flight `performMapChange`, starts a new one, and stores it as the current
    /// `mapChangeTask` — the single choke point both of `handleMapChange`'s independent call sites
    /// route through, so a slower, stale request can't overwrite a newer one's state.
    private func replaceMapChangeTask(isGameMaster: Bool) -> Task<Void, Never> {
        mapChangeTask?.cancel()
        let task = Task { await performMapChange(isGameMaster: isGameMaster) }
        mapChangeTask = task
        return task
    }

    private func performMapChange(isGameMaster: Bool) async {
        updateRole(isGameMaster)

        guard let currentItemId = mapRoot.mapGameControllable.gameModel.currentItemId else {
            clearPinSelection()
            currentMapId = nil
            clearBoardImage()
            syncPawnsWithMapPins()
            Logger.gameTable.debug("No current map selected in game")
            return
        }

        guard let mapModel = await mapModel(for: currentItemId) else {
            clearPinSelection()
            currentMapId = nil
            clearBoardImage()
            syncPawnsWithMapPins()
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }
        // Re-validate after the suspension above: a newer call may already have superseded this one.
        guard !Task.isCancelled else { return }

        let mapChanged = currentItemId != currentMapId
        let photoMetadata = mapModel.photoId.flatMap(photoMetadata(for:))
        let photoChanged = mapModel.photoId != currentPhotoId
            || photoMetadata?.version != currentPhotoVersion
            || photoMetadata?.degrees != currentMapDegrees
        if mapChanged {
            clearPinSelection()
            clearPinPhoto()
            sharedPhotoPinIds = []
            // The previous map's image must not survive under the new map's id: if this request is
            // cancelled while the photo loads, the next one has to reload rather than composite the
            // stale image with the new map's rooms.
            currentMapImage = nil
            currentPhotoId = nil
            currentPhotoVersion = nil
            currentMapDegrees = 0
            fogSignature = nil
        }
        currentMapId = currentItemId

        if mapChanged || photoChanged || currentMapImage == nil {
            await loadMapPhoto(mapModel: mapModel)
        } else {
            await replaceFogOfWarTask().value
        }
        guard !Task.isCancelled else { return }
        syncPawnsWithMapPins()
    }

    /// Loads the map's photo and renders the board. The photo/version/degrees/signature are
    /// committed together, only after the render was applied, so a cancelled or failed load never
    /// leaves state describing an image the board isn't showing.
    private func loadMapPhoto(mapModel: MapModel) async {
        guard let photoId = mapModel.photoId else {
            currentPhotoId = nil
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = nil
            clearBoardImage()
            fogSignature = Self.renderSignature(of: mapModel, degrees: 0, isGameMaster: renderIsGameMaster)
            Logger.gameTable.debug("Map has no photo")
            return
        }

        let metadata = photoMetadata(for: photoId)
        let (image, degrees) = await photoRoot.fetchPhotoImage(for: photoId, useGame: true) ?? (nil, 0)
        guard !Task.isCancelled else { return }
        guard let image else {
            currentPhotoId = photoId
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = metadata?.version
            clearBoardImage()
            Logger.gameTable.error("Failed to load photo for the current map")
            return
        }

        let signature = Self.renderSignature(of: mapModel, degrees: degrees, isGameMaster: renderIsGameMaster)
        guard await renderBoard(image: image, degrees: degrees, mapModel: mapModel) else { return }
        currentPhotoId = photoId
        currentMapImage = image
        currentMapDegrees = degrees
        currentPhotoVersion = metadata?.version
        fogSignature = signature
        Logger.gameTable.debug("Map updated (rotation: \(degrees, privacy: .public)°, GM: \(self.isGameMaster, privacy: .public))")
    }

    /// Cancels any in-flight fog recomposite, starts a new one, and stores it as the current
    /// `fogOfWarTask` — the single choke point every fog-affecting entry point routes through so
    /// overlapping requests (rapid room toggling, a remote update mid-toggle) supersede rather than
    /// race each other. Callers that need the result await the returned task directly instead of
    /// re-reading `fogOfWarTask`, which a nested call may already have replaced.
    @discardableResult
    func replaceFogOfWarTask() -> Task<Void, Never> {
        fogOfWarTask?.cancel()
        let task = Task { await updateFogOfWar() }
        fogOfWarTask = task
        return task
    }

    /// Rebuilds fog only when a value that affects the rendered board changed. Checks cancellation
    /// after every suspension point so a recomposite superseded by a newer one can't apply its
    /// now-stale result on top.
    private func updateFogOfWar() async {
        guard let currentItemId = currentMapId else {
            Logger.gameTable.debug("No current map to update fog of war")
            return
        }
        guard let mapModel = await mapModel(for: currentItemId) else {
            clearBoardImage()
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }
        guard !Task.isCancelled else { return }
        let metadata = mapModel.photoId.flatMap(photoMetadata(for:))
        if metadata?.version != currentPhotoVersion
            || metadata?.degrees != currentMapDegrees {
            await loadMapPhoto(mapModel: mapModel)
            return
        }
        guard let mapImage = currentMapImage,
              currentPhotoId == mapModel.photoId else {
            await loadMapPhoto(mapModel: mapModel)
            return
        }

        let signature = Self.renderSignature(
            of: mapModel,
            degrees: currentMapDegrees,
            isGameMaster: renderIsGameMaster
        )
        guard signature != fogSignature else { return }
        guard await renderBoard(image: mapImage, degrees: currentMapDegrees, mapModel: mapModel) else { return }
        fogSignature = signature
        Logger.gameTable.debug("Fog of war updated - \(mapModel.entries.filter { !$0.isShown }.count, privacy: .public) hidden areas (GM: \(self.isGameMaster, privacy: .public))")
    }

    /// Renders the board off the main actor and applies it unless something newer (another render or
    /// a board clear) started in the meantime. Fog and map-load tasks are independent, so without
    /// the generation check a slow render for an old map could land on top of a newer one.
    private func renderBoard(image: AKImage, degrees: Double, mapModel: MapModel) async -> Bool {
        boardRenderGeneration += 1
        let generation = boardRenderGeneration
        let applied = await setup.board.updateMap(
            image: image,
            degrees: degrees,
            mapModel: mapModel,
            isGameMaster: renderIsGameMaster,
            shouldApply: { [weak self] in self?.boardRenderGeneration == generation }
        )
        if applied {
            setup.board.updateAccessibility(
                gameMasterSummary: isGameMaster
                    ? (mapModel.name, mapModel.entries.filter { !$0.isShown }.count, mapModel.entries.count)
                    : nil
            )
        }
        return applied
    }

    /// The effective GM/fog flag used for rendering only — real role-gating (`isGameMaster`,
    /// checked everywhere a mutation is permission-gated) stays untouched by the local preview.
    /// Reader and player both preview as fog-limited today; the 3D board has no separate "full view
    /// without GM overlays" render path the way the 2D map's reader mode does.
    private var renderIsGameMaster: Bool {
        isGameMaster && displayMode != .player
    }

    /// Includes all board inputs, not merely room visibility, so edits to room geometry, map
    /// dimensions, display configuration, photo, and role render.
    private static func renderSignature(
        of mapModel: MapModel,
        degrees: Double,
        isGameMaster: Bool
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(mapModel.id)
        hasher.combine(mapModel.photoId)
        hasher.combine(mapModel.width)
        hasher.combine(mapModel.height)
        hasher.combine(degrees)
        hasher.combine(isGameMaster)
        hasher.combine(mapModel.displayConfig)
        for entry in mapModel.entries {
            hasher.combine(entry.id)
            hasher.combine(entry.coordinates)
            hasher.combine(entry.isHexGrid)
            hasher.combine(entry.isShown)
            hasher.combine(entry.focused)
        }
        return hasher.finalize()
    }
}

#endif
