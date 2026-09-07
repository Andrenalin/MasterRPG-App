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
    // MARK: - Map Sync & Fog of War

    /// Refreshes the standalone tabletop from the current game selection. The
    /// method deliberately rechecks the same map id because mapState updates can
    /// alter its photo, rooms, pins, or role without changing navigation.
    func refreshCurrentMap(isGameMaster: Bool) async {
        await handleMapChange(isGameMaster: isGameMaster)
    }

    func handleMapChange(isGameMaster: Bool) async {
        await replaceMapChangeTask(isGameMaster: isGameMaster).value
    }

    /// Cancels any in-flight `performMapChange`, starts a new one, and stores it as the
    /// current `mapChangeTask` — the single choke point both of `handleMapChange`'s
    /// independent call sites route through, so a slower, stale request (e.g. the initial
    /// appear's plain `.task` racing the `.task(id:)` map-selection watcher) can't overwrite
    /// a newer one's state. Mirrors `replaceFogOfWarTask` below. See CODE_AUDIT_9 §3.2.
    @discardableResult
    private func replaceMapChangeTask(isGameMaster: Bool) -> Task<Void, Never> {
        mapChangeTask?.cancel()
        let task = Task { await performMapChange(isGameMaster: isGameMaster) }
        mapChangeTask = task
        return task
    }

    private func performMapChange(isGameMaster: Bool) async {
        let roleChanged = self.isGameMaster != isGameMaster
        self.isGameMaster = isGameMaster

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
        // Re-validate after the suspension above: a newer call may have
        // already superseded this one via `replaceMapChangeTask`. See
        // CODE_AUDIT_9 §3.2.
        guard !Task.isCancelled else { return }

        let mapChanged = currentItemId != currentMapId
        let photoMetadata = mapModel.photoId.flatMap(photoMetadata(for:))
        let photoChanged = mapModel.photoId != currentPhotoId
            || photoMetadata?.version != currentPhotoVersion
            || photoMetadata?.degrees != currentMapDegrees
        if mapChanged {
            clearPinSelection()
            fogSignature = nil
        }
        if roleChanged {
            fogSignature = nil
        }
        resetViewportPanIfFocusedRoomChanged(entries: mapModel.entries)
        currentMapId = currentItemId

        if mapChanged || photoChanged || currentMapImage == nil {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
        } else {
            await replaceFogOfWarTask(isGameMaster: isGameMaster).value
        }
        guard !Task.isCancelled else { return }
        syncPawnsWithMapPins()
    }

    private func loadMapPhoto(mapModel: MapModel, isGameMaster: Bool) async {
        currentPhotoId = mapModel.photoId
        guard let photoId = mapModel.photoId else {
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = nil
            fogSignature = Self.renderSignature(
                of: mapModel,
                degrees: 0,
                isGameMaster: renderIsGameMaster
            )
            setup.board.clearMap()
            Logger.gameTable.debug("Map has no photo")
            return
        }

        let metadata = photoMetadata(for: photoId)
        let (image, degrees) = await photoRoot.fetchPhotoImage(for: photoId, useGame: true) ?? (nil, 0)
        guard !Task.isCancelled else { return }
        guard let image else {
            currentMapImage = nil
            currentMapDegrees = 0
            currentPhotoVersion = metadata?.version
            fogSignature = nil
            setup.board.clearMap()
            Logger.gameTable.error("Failed to load photo for the current map")
            return
        }

        currentMapImage = image
        currentMapDegrees = degrees
        currentPhotoVersion = metadata?.version
        fogSignature = Self.renderSignature(
            of: mapModel,
            degrees: degrees,
            isGameMaster: renderIsGameMaster
        )
        setup.board.updateMap(
            image: image,
            degrees: degrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: renderIsGameMaster,
            panOffset: manualViewportOffset
        )
        Logger.gameTable.debug("Map updated (rotation: \(degrees, privacy: .public)°, GM: \(isGameMaster, privacy: .public))")
    }

    /// Cancels any in-flight fog recomposite, starts a new one, and stores it as the current
    /// `fogOfWarTask` — the single choke point every fog-affecting entry point routes through
    /// so overlapping requests (rapid room toggling, a toolbar action mid-drag) supersede
    /// rather than race each other. Callers that need to wait for the result (room
    /// toggle/focus, "show/hide all", a map change) await the returned task directly instead
    /// of re-reading `fogOfWarTask`, which a nested call could have already replaced by the
    /// time they'd read it back. See CODE_AUDIT §5.5.
    @discardableResult
    func replaceFogOfWarTask(isGameMaster: Bool) -> Task<Void, Never> {
        fogOfWarTask?.cancel()
        let task = Task { await updateFogOfWar(isGameMaster: isGameMaster) }
        fogOfWarTask = task
        return task
    }

    /// Rebuilds fog only when a value that affects the rendered board changed. Checks
    /// cancellation after every suspension point so a recomposite superseded by a newer one
    /// (via `replaceFogOfWarTask`) can't still apply its now-stale result on top. See
    /// CODE_AUDIT §5.5.
    func updateFogOfWar(isGameMaster: Bool) async {
        self.isGameMaster = isGameMaster
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
        resetViewportPanIfFocusedRoomChanged(entries: mapModel.entries)
        let metadata = mapModel.photoId.flatMap(photoMetadata(for:))
        if metadata?.version != currentPhotoVersion
            || metadata?.degrees != currentMapDegrees {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }
        guard let mapImage = currentMapImage,
              currentPhotoId == mapModel.photoId else {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }

        let signature = Self.renderSignature(
            of: mapModel,
            degrees: currentMapDegrees,
            isGameMaster: renderIsGameMaster
        )
        guard signature != fogSignature else { return }
        guard !Task.isCancelled else { return }
        fogSignature = signature

        setup.board.updateMap(
            image: mapImage,
            degrees: currentMapDegrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: renderIsGameMaster,
            panOffset: manualViewportOffset
        )
        Logger.gameTable.debug("Fog of war updated - \(mapModel.entries.filter { !$0.isShown }.count, privacy: .public) hidden areas (GM: \(isGameMaster, privacy: .public))")
    }

    /// The effective GM/fog flag used for rendering only — real role-gating
    /// (`isGameMaster`, checked everywhere a mutation is permission-gated)
    /// stays untouched by the local preview. Reader and player both preview
    /// as fog-limited today; the 3D board has no separate "full view without
    /// GM overlays" render path the way the 2D map's reader mode does.
    private var renderIsGameMaster: Bool {
        isGameMaster && displayMode != .player
    }

    /// Includes all board inputs, not merely room visibility, so edits to room
    /// geometry, map dimensions, display configuration, photo, and role render.
    ///
    /// Deliberately excludes `manualViewportOffset`: `boardFocusRect` never
    /// applies it (see its own doc comment), so folding it in here used to
    /// bust this cache on every pan-drag delta and trigger a full fog/board
    /// recomposite for a value with no rendering effect. See CODE_AUDIT_10
    /// §7.1.
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
