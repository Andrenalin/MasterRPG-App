// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import os.log

extension GameSetup {
    /// Syncs pin tokens (players and monsters) with the current map pins,
    /// id-matched: updates existing, creates missing, removes stale tokens.
    /// Returns pinId → photoId for tokens that still need their photo texture.
    func syncPins(
        mapModel: MapModel?,
        mapImage: AKImage?,
        degrees: Double,
        isGameMaster: Bool,
        activeAttackerPinId: UUID?,
        viewportPan: CGPoint,
        healthPercent: (MapPinModel) -> Double?
    ) -> [UUID: UUID] {
        let allPins: [MapPinModel]
        if let mapModel {
            let pointerPins = mapModel.pointer.isShown ? [mapModel.pointer] : []
            allPins = mapModel.mapPins + pointerPins
        } else {
            allPins = []
        }
        // Visibility: the master sees every pin (hidden ones dimmed); players
        // see a pin when it is shown and — for monsters — not covered by fog.
        var seenPinIds: Set<UUID> = []
        let targetPins = allPins.filter { seenPinIds.insert($0.id).inserted }.filter { pin in
            if isGameMaster { return true }
            guard pin.isShown else { return false }
            if pin.id == mapModel?.pointer.id { return true }
            if pin.isPlayer { return true }
            return mapModel.map { !$0.isLocationHiddenForPlayers(pin.location) } ?? true
        }

        let projection = projection(mapModel: mapModel, mapImage: mapImage, degrees: degrees, viewportPan: viewportPan)

        // Same conversion the 2D map applies to a pin's base size (points ×
        // pinScale), just projected into table meters instead of screen
        // points, so a token occupies the same fraction of the table that its
        // pin occupies of the map image.
        let pointsToMeters: Float = if let projection {
            Float(mapModel?.pinScale ?? 1) * projection.metersPerPoint
        } else {
            MapTableProjection.fallbackPointsToMeters
        }

        var photoLoads: [UUID: UUID] = [:]
        var lineupIndex = 0
        var keptIds: Set<UUID> = []
        let existingPawns = Dictionary(
            pinPawns.map { ($0.pinId, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        for pin in targetPins {
            keptIds.insert(pin.id)
            let position: SIMD3<Float>
            if let projection {
                position = projection.tablePosition(for: pin.location)
            } else {
                // No map on the table: line the tokens up outside the map area
                // on the near edge so joining players are visible immediately.
                position = SIMD3<Float>(-0.15 + 0.06 * Float(lineupIndex), MapTableProjection.pinHeight, MapTableProjection.maxPlaneDepth / 2 + 0.05)
                lineupIndex += 1
            }
            let hiddenForMaster = isGameMaster && !pin.isShown
            if let pawn = existingPawns[pin.id] {
                pawn.update(
                    pin: pin,
                    position: position,
                    hiddenForMaster: hiddenForMaster,
                    activeAttackerPinId: activeAttackerPinId,
                    healthPercent: healthPercent(pin),
                    pointsToMeters: pointsToMeters
                )
                if pawn.loadedPhotoId != pin.photoId, let photoId = pin.photoId {
                    photoLoads[pin.id] = photoId
                }
            } else {
                let pawn = PinPawn(pin: pin, pointsToMeters: pointsToMeters)
                pawn.update(
                    pin: pin,
                    position: position,
                    hiddenForMaster: hiddenForMaster,
                    activeAttackerPinId: activeAttackerPinId,
                    healthPercent: healthPercent(pin),
                    pointsToMeters: pointsToMeters
                )
                pinPawns.append(pawn)
                pinContainer.addChild(pawn.entity)
                if let photoId = pin.photoId {
                    photoLoads[pin.id] = photoId
                }
            }
        }

        for pawn in pinPawns where !keptIds.contains(pawn.pinId) {
            pawn.entity.removeFromParent()
        }
        pinPawns.removeAll { !keptIds.contains($0.pinId) }

        Logger.gameTable.debug("Pin sync: \(self.pinPawns.count, privacy: .public) tokens, \(photoLoads.count, privacy: .public) photo loads pending")
        return photoLoads
    }

    /// Syncs invisible room fog hit-test volumes with the current map's
    /// entries so a room can be double-tapped/long-pressed directly on the
    /// table. Clears every hit area when there's no map or image to project
    /// coordinates against — the room menu still works then, only the
    /// on-table gesture is unavailable.
    func syncRooms(mapModel: MapModel?, mapImage: AKImage?, degrees: Double, viewportPan: CGPoint) {
        guard let mapModel, let projection = projection(mapModel: mapModel, mapImage: mapImage, degrees: degrees, viewportPan: viewportPan) else {
            for area in roomHitAreas {
                area.entity.removeFromParent()
            }
            roomHitAreas.removeAll()
            return
        }

        let existingAreas = Dictionary(
            roomHitAreas.map { ($0.roomId, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        var keptIds: Set<UUID> = []

        for entry in mapModel.entries {
            keptIds.insert(entry.id)
            if let area = existingAreas[entry.id] {
                area.update(entry: entry, projection: projection)
            } else {
                let area = RoomHitArea(entry: entry, projection: projection)
                roomHitAreas.append(area)
                roomHitContainer.addChild(area.entity)
            }
        }

        for area in roomHitAreas where !keptIds.contains(area.roomId) {
            area.entity.removeFromParent()
        }
        roomHitAreas.removeAll { !keptIds.contains($0.roomId) }
    }

    /// Shared by `syncPins` and `syncRooms`: the map/image → table-plane
    /// coordinate conversion, authoritative from `MapModel` when available.
    private func projection(mapModel: MapModel?, mapImage: AKImage?, degrees: Double, viewportPan: CGPoint) -> MapTableProjection? {
        if let mapModel, mapModel.width > 0, mapModel.height > 0 {
            // MapModel is authoritative: room/pin coordinates were already
            // normalized into this oriented canvas by the 2D editor.
            let imageSize = CGSize(width: mapModel.width, height: mapModel.height)
            return MapTableProjection(
                imageSize: imageSize,
                degrees: 0,
                focusRect: GameTableModel.boardFocusRect(
                    entries: mapModel.entries,
                    imageSize: imageSize,
                    panOffset: viewportPan
                )
            )
        } else if let mapImage {
            return MapTableProjection(imageSize: mapImage.fixedSize, degrees: degrees)
        } else {
            return nil
        }
    }
}

extension GameTableModel {
    @MainActor
    func resetGame() {
        syncPawnsWithMapPins()
    }

    /// Syncs pin tokens with the pins of the current map (may be nil — player
    /// pins then line up outside the map area) and loads missing pin photos.
    @MainActor
    func syncPawnsWithMapPins() {
        let mapModel = currentMapModel()
        let battleRound = mapRoot.mapGameControllable.battleRoundModel
        let activeAttackerPinId = battleRound.isRunning ? battleRound.activePinId : nil
        let photoLoads = setup.syncPins(
            mapModel: mapModel,
            mapImage: currentMapImage,
            degrees: currentMapDegrees,
            isGameMaster: isGameMaster,
            activeAttackerPinId: activeAttackerPinId,
            viewportPan: manualViewportOffset,
            healthPercent: healthPercent(for:)
        )
        setup.syncRooms(
            mapModel: mapModel,
            mapImage: currentMapImage,
            degrees: currentMapDegrees,
            viewportPan: manualViewportOffset
        )
        updateSelectedPinState(mapModel: mapModel)
        for (pinId, photoId) in photoLoads {
            guard beginPinPhotoLoad(pinId: pinId, photoId: photoId) else { continue }
            let task = Task { [weak self] in
                await self?.loadPinThumbnail(pinId: pinId, photoId: photoId)
            }
            trackThumbnailTask(for: pinId, task)
        }
    }

    /// Mirrors `MapPinView`'s own `healthPercent`: prefers a live-computed
    /// percent from the pin's linked hit-points entry whenever it's a
    /// tracked battle combatant (only true on the game master's own screen
    /// — a player has no local Character to read one from), falling back to
    /// the pin's last *broadcast* `healthPercent` otherwise. Both paths
    /// render through `MapPinModel.healthBorderColor(for:)`.
    private func healthPercent(for pin: MapPinModel) -> Double? {
        guard let combatant = mapRoot.mapGameControllable.battleRoundModel.combatant(pinId: pin.id) else {
            return pin.healthPercent
        }
        return mapRoot.mapGameControllable.healthPercent(for: combatant)
    }
}

/// Maps the already-oriented 2D map coordinates onto the horizontal board.
/// `MapModel.resetImage` rescales rooms and pins when the photo rotates, so the
/// projection swaps dimensions for 90°/270° but must not rotate coordinates a
/// second time. Shared by every platform's `GameSetup` — see CODE_AUDIT §9.1.
struct MapTableProjection {
    /// The bounding box the map fits into on the board — the table's own
    /// extents inset by `GameMetrics.mapMargin` on every side, leaving that
    /// margin free for each seat's dice (see `PlayerSeat.diceLayout`). The
    /// map's actual rendered size (`planeWidth`/`planeDepth` below) fits
    /// inside this box preserving the source image's aspect ratio, so it
    /// only fills both dimensions when the image's aspect ratio happens to
    /// match the box's.
    // `maxPlaneWidth` is the board's X-extent, `maxPlaneDepth` its Z-extent
    // — the table's long dimension is now Z (`tableLength`), not X. See
    // `PlayerSeat.seatPoses`'s own doc for why.
    static let maxPlaneWidth: Float = GameMetrics.tableWidth - (GameMetrics.mapMargin * 2)
    static let maxPlaneDepth: Float = GameMetrics.tableLength - (GameMetrics.mapMargin * 2)
    /// Token height above the board surface.
    static let pinHeight: Float = GameMetrics.tableThickness + GameMetrics.mapSurfaceClearance
    /// Pin diameter (meters) used when no map is on the table and there's no
    /// image to derive a conversion factor from — matches a "normal" 2D pin
    /// (44pt) rendered at the table's former fixed 0.04 m default.
    static let fallbackPointsToMeters: Float = 0.04 / 44

    let imageSize: CGSize
    let degrees: Double
    let planeWidth: Float
    let planeDepth: Float
    /// The portion of `imageSize` mapped onto the full board plane — always
    /// the whole image today, since the 3D board never crops/zooms into a
    /// focused room (see `GameTableModel.boardFocusRect`; only the 2D map
    /// still does). A pin located outside this rect projects beyond the
    /// physical table edges.
    let focusRect: CGRect

    /// Table meters per source-image point, at this projection's scale.
    /// Multiplying a 2D pin's point size by this (and by `MapModel.pinScale`)
    /// gives the 3D token the same size relative to the table that the pin
    /// has relative to the map image.
    ///
    /// Uses `focusRect` rather than assuming it always equals `imageSize` —
    /// `boardFocusRect` returns the full image today, but any future crop
    /// would need pins to grow by the same magnification to stay correctly
    /// sized relative to the map around them, matching how the 2D map's own
    /// room-focus zoom already scales its pins along with the map image
    /// (`MapEditorCanvas`'s `scaleEffect` covers both together).
    var metersPerPoint: Float {
        guard focusRect.width > 0 else { return 0 }
        return planeWidth / Float(focusRect.width)
    }

    init(imageSize: CGSize, degrees: Double, focusRect: CGRect? = nil) {
        let normalizedDegrees = Self.normalizedDegrees(degrees)
        let orientedSize = Self.orientedImageSize(imageSize, degrees: normalizedDegrees)
        let safeSize = CGSize(
            width: max(1, orientedSize.width),
            height: max(1, orientedSize.height)
        )
        self.imageSize = safeSize
        self.degrees = normalizedDegrees
        self.focusRect = focusRect ?? CGRect(origin: .zero, size: safeSize)
        let aspectRatio = safeSize.width / safeSize.height
        // Fit inside the (possibly non-square) `maxPlaneWidth` ×
        // `maxPlaneDepth` box preserving aspect ratio: compare the image's
        // aspect ratio against the box's own to find which dimension is the
        // constraining one, rather than assuming width always is.
        let boxAspectRatio = CGFloat(Self.maxPlaneWidth / Self.maxPlaneDepth)
        if aspectRatio > boxAspectRatio {
            planeWidth = Self.maxPlaneWidth
            planeDepth = Self.maxPlaneWidth / Float(aspectRatio)
        } else {
            planeDepth = Self.maxPlaneDepth
            planeWidth = Self.maxPlaneDepth * Float(aspectRatio)
        }
    }

    func tablePosition(for location: CGPoint) -> SIMD3<Float> {
        let normalizedX = (location.x - focusRect.minX) / focusRect.width
        let normalizedY = (location.y - focusRect.minY) / focusRect.height
        let tableX = Float(normalizedX - 0.5) * planeWidth
        let tableZ = Float(normalizedY - 0.5) * planeDepth
        return SIMD3<Float>(tableX, Self.pinHeight, tableZ)
    }

    /// Exact inverse of `tablePosition(for:)`, clamped to the full image
    /// bounds (not just `focusRect`) since a pin may be dropped anywhere on
    /// the table.
    func mapLocation(for position: SIMD3<Float>) -> CGPoint {
        let x = (CGFloat(position.x / planeWidth) + 0.5) * focusRect.width + focusRect.minX
        let y = (CGFloat(position.z / planeDepth) + 0.5) * focusRect.height + focusRect.minY
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }

    static func orientedImageSize(_ size: CGSize, degrees: Double) -> CGSize {
        swapsAxes(for: normalizedDegrees(degrees))
            ? CGSize(width: size.height, height: size.width)
            : size
    }

    static func swapsAxes(for degrees: Double) -> Bool {
        abs(degrees - 90) < 0.001 || abs(degrees - 270) < 0.001
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
#endif
