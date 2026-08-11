// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import RPGTabletopGameContent
import Spatial
import os.log
import MapRPG
import CoreRPG

enum GameMetrics {
    static let tableEdge: Float = 0.7
    static let tableThickness: Float = 0.0146
    static let mapSurfaceClearance: Float = 0.0005
    static let playerAreaDistanceFromCenter: Float = 0.29
    static let smallHeight: Float = 0.001
    static let boardHeight: Float = 0.055
    static let playerAreaSize: SIMD2<Float> = SIMD2(0.4, 0.1)
    static let playerHandSize: SIMD2<Float> = SIMD2(0.2, 0.1)
}

@MainActor
class GameSetup {
    let root: Entity
    var setup: TableSetup
    let board: Board
    var pinPawns: [PinPawn] = []
    var roomHitAreas: [RoomHitArea] = []
    var seats: [PlayerSeat] = []
    /// Container for dynamically-added pin entities. Parented to root so they
    /// appear in the scene without going through TabletopKit's frozen TableSetup.
    let pinContainer: Entity
    /// Container for invisible room fog hit-test volumes, parallel to `pinContainer`.
    let roomHitContainer: Entity

    // This is an incrementing counter to generate unique IDs for each piece of equipment.
    struct IdentifierGenerator {
        private var count = 0

        mutating func newId() -> Int {
            count += 1
            return count
        }
    }
    var idGenerator = IdentifierGenerator()

    /*
     The table has a board in the center,
     with a hand and a pawn for each player around the sides.
     The side without a seat has the deck and the die.
     
            +---+
            |die|   +------+
            +---+   | deck |
                    +------+
       pawn
       +-+     +---+-+-+-+-+-+-+---+
       +-+     |   | | | | | | |   |
               +---+-+-+-+-+-+-+---+  +-----+
     +-----+   |---|           |---|  |     |
     |     |   |---|           |---|  |hand |
     |hand |   |---|  board    |---|  |     |
     |     |   |---|           |---|  |     |
     |     |   |---|           |---|  |     |
     |     |   +---+-+-+-+-+-+-+---+  +-----+
     +-----+   |   | | | | | | |   |
               +---+-+-+-+-+-+-+---+    +-+
                                        +-+
           +-+   +-----------+          pawn
           +-+   |           |
           pawn  |   hand    |
                 +-----------+
     */
    init(root: Entity) {
        self.root = root
        PinComponent.registerComponent()
        RoomComponent.registerComponent()
        pinContainer = Entity()
        pinContainer.name = "PinContainer"
        root.addChild(pinContainer)
        roomHitContainer = Entity()
        roomHitContainer.name = "RoomHitContainer"
        root.addChild(roomHitContainer)
        setup = TableSetup(tabletop: Table())

        for (index, pose) in PlayerSeat.seatPoses.enumerated() {
            let seat = PlayerSeat(id: TableSeatIdentifier(index), pose: pose)
            seats.append(seat)
            setup.add(seat: seat)
        }

        // The board is a static root-owned surface. Keeping it out of
        // TabletopKit prevents its automatic tabletop resting transform from
        // moving the plane inside the bottom-origin wood mesh.
        board = Board()
        root.addChild(board.entity)

        let die20 = Die20(id: EquipmentIdentifier(self.idGenerator.newId()))
        setup.add(equipment: die20)
    }
    
    /// Syncs pin tokens (players and monsters) with the current map pins,
    /// id-matched: updates existing, creates missing, removes stale tokens.
    /// Returns pinId → photoId for tokens that still need their photo texture.
    func syncPins(
        mapModel: MapModel?,
        mapImage: AKImage?,
        degrees: Double,
        isGameMaster: Bool,
        activeAttackerPinId: UUID?
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

        let projection = projection(mapModel: mapModel, mapImage: mapImage, degrees: degrees)

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
                position = SIMD3<Float>(-0.15 + 0.06 * Float(lineupIndex), MapTableProjection.pinHeight, MapTableProjection.mapSize / 2 + 0.05)
                lineupIndex += 1
            }
            let hiddenForMaster = isGameMaster && !pin.isShown
            if let pawn = existingPawns[pin.id] {
                pawn.update(
                    pin: pin,
                    position: position,
                    hiddenForMaster: hiddenForMaster,
                    activeAttackerPinId: activeAttackerPinId,
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
    func syncRooms(mapModel: MapModel?, mapImage: AKImage?, degrees: Double) {
        guard let mapModel, let projection = projection(mapModel: mapModel, mapImage: mapImage, degrees: degrees) else {
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
    private func projection(mapModel: MapModel?, mapImage: AKImage?, degrees: Double) -> MapTableProjection? {
        if let mapModel, mapModel.width > 0, mapModel.height > 0 {
            // MapModel is authoritative: room/pin coordinates were already
            // normalized into this oriented canvas by the 2D editor.
            return MapTableProjection(
                imageSize: CGSize(width: mapModel.width, height: mapModel.height),
                degrees: 0
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
            activeAttackerPinId: activeAttackerPinId
        )
        setup.syncRooms(mapModel: mapModel, mapImage: currentMapImage, degrees: currentMapDegrees)
        updateSelectedPinState(mapModel: mapModel)
        for (pinId, photoId) in photoLoads {
            guard beginPinPhotoLoad(pinId: pinId, photoId: photoId) else { continue }
            Task { [weak self] in
                await self?.loadPinThumbnail(pinId: pinId, photoId: photoId)
            }
        }
    }
}

/// Projects between 2D map pixel coordinates and 3D table coordinates.
struct MapTableProjection {
    /// Rendered map size on the board (5 cm border on all sides).
    static let mapSize: Float = GameMetrics.tableEdge - (0.05 * 2)
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

    /// Table meters per source-image point, at this projection's scale.
    /// Multiplying a 2D pin's point size by this (and by `MapModel.pinScale`)
    /// gives the 3D token the same size relative to the table that the pin
    /// has relative to the map image.
    var metersPerPoint: Float {
        guard imageSize.width > 0 else { return 0 }
        return planeWidth / Float(imageSize.width)
    }

    init(imageSize: CGSize, degrees: Double) {
        let normalizedDegrees = Self.normalizedDegrees(degrees)
        let orientedSize = Self.orientedImageSize(imageSize, degrees: normalizedDegrees)
        let safeSize = CGSize(
            width: max(1, orientedSize.width),
            height: max(1, orientedSize.height)
        )
        self.imageSize = safeSize
        self.degrees = normalizedDegrees
        let aspectRatio = safeSize.width / safeSize.height
        if aspectRatio > 1.0 {
            planeWidth = Self.mapSize
            planeDepth = Self.mapSize / Float(aspectRatio)
        } else {
            planeDepth = Self.mapSize
            planeWidth = Self.mapSize * Float(aspectRatio)
        }
    }

    func tablePosition(for location: CGPoint) -> SIMD3<Float> {
        let normalizedX = location.x / imageSize.width
        let normalizedY = location.y / imageSize.height
        let tableX = Float(normalizedX - 0.5) * planeWidth
        let tableZ = Float(normalizedY - 0.5) * planeDepth
        return SIMD3<Float>(tableX, Self.pinHeight, tableZ)
    }

    /// Exact inverse of `tablePosition(for:)`, clamped to the image bounds.
    func mapLocation(for position: SIMD3<Float>) -> CGPoint {
        let x = (CGFloat(position.x / planeWidth) + 0.5) * imageSize.width
        let y = (CGFloat(position.z / planeDepth) + 0.5) * imageSize.height
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
