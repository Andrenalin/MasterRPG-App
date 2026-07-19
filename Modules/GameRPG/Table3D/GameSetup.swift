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
    var board: Board
    var pinPawns: [PinPawn] = []
    var seats: [PlayerSeat] = []
    /// Container for dynamically-added pin entities. Parented to root so they
    /// appear in the scene without going through TabletopKit's frozen TableSetup.
    let pinContainer: Entity

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
        pinContainer = Entity()
        pinContainer.name = "PinContainer"
        root.addChild(pinContainer)
        setup = TableSetup(tabletop: Table())

        for (index, pose) in PlayerSeat.seatPoses.enumerated() {
            let seat = PlayerSeat(id: TableSeatIdentifier(index), pose: pose)
            seats.append(seat)
            setup.add(seat: seat)
        }

        // The board owns only the live battle-map surface.
        board = Board(id: EquipmentIdentifier(self.idGenerator.newId()))
        setup.add(equipment: board)

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

        let projection: MapTableProjection? = if let mapModel,
                                                  mapModel.width > 0,
                                                  mapModel.height > 0 {
            // MapModel is authoritative: room/pin coordinates were already
            // normalized into this oriented canvas by the 2D editor.
            MapTableProjection(
                imageSize: CGSize(width: mapModel.width, height: mapModel.height),
                degrees: 0
            )
        } else if let mapImage {
            MapTableProjection(imageSize: mapImage.fixedSize, degrees: degrees)
        } else {
            nil
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
                    activeAttackerPinId: activeAttackerPinId
                )
                if pawn.loadedPhotoId != pin.photoId, let photoId = pin.photoId {
                    photoLoads[pin.id] = photoId
                }
            } else {
                let pawn = PinPawn(pin: pin)
                pawn.update(
                    pin: pin,
                    position: position,
                    hiddenForMaster: hiddenForMaster,
                    activeAttackerPinId: activeAttackerPinId
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

    let imageSize: CGSize
    let degrees: Double
    let planeWidth: Float
    let planeDepth: Float

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
