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
    static let playerAreaDistanceFromCenter: Float = 0.29
    static let boardEdge: Float = 0.4
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

        // Create board with battle map image
        // Replace "battleMap" with your actual image asset name
        board = Board(id: EquipmentIdentifier(self.idGenerator.newId()))
        setup.add(equipment: board)

        let die = Die(id: EquipmentIdentifier(self.idGenerator.newId()))
        setup.add(equipment: die)

        let die20 = Die20(id: EquipmentIdentifier(self.idGenerator.newId()))
        setup.add(equipment: die20)
    }
    
    /// Syncs pin tokens (players and monsters) with the current map pins,
    /// id-matched: updates existing, creates missing, removes stale tokens.
    /// Returns pinId → photoId for tokens that still need their photo texture.
    func syncPins(mapModel: MapModel?, mapImage: AKImage?, degrees: Double, isGameMaster: Bool) -> [UUID: UUID] {
        let allPins = mapModel?.mapPins ?? []
        // Visibility: the master sees every pin (hidden ones dimmed); players
        // see a pin when it is shown and — for monsters — not covered by fog.
        let targetPins = allPins.filter { pin in
            if isGameMaster { return true }
            guard pin.isShown else { return false }
            if pin.isPlayer { return true }
            return mapModel.map { !$0.isLocationHiddenForPlayers(pin.location) } ?? true
        }

        var projection: MapTableProjection?
        if let mapImage, let cgImage = mapImage.cgImage {
            projection = MapTableProjection(imageSize: CGSize(width: cgImage.width, height: cgImage.height), degrees: degrees)
        }

        var photoLoads: [UUID: UUID] = [:]
        var lineupIndex = 0
        var keptIds: Set<UUID> = []

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
            if let pawn = pinPawns.first(where: { $0.pinId == pin.id }) {
                pawn.update(pin: pin, position: position, hiddenForMaster: hiddenForMaster)
                if pawn.loadedPhotoId != pin.photoId, let photoId = pin.photoId {
                    photoLoads[pin.id] = photoId
                }
            } else {
                let pawn = PinPawn(pin: pin)
                pawn.update(pin: pin, position: position, hiddenForMaster: hiddenForMaster)
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
        var mapModel: MapModel?
        if let mapId = currentMapId {
            mapModel = mapRoot.itemControllable.itemSync(for: mapId) as? MapModel
        }
        let photoLoads = setup.syncPins(mapModel: mapModel, mapImage: currentMapImage, degrees: currentMapDegrees, isGameMaster: isGameMaster)
        for (pinId, photoId) in photoLoads {
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
    static let pinHeight: Float = 0.03

    let imageSize: CGSize
    let degrees: Double
    let planeWidth: Float
    let planeDepth: Float

    init(imageSize: CGSize, degrees: Double) {
        self.imageSize = imageSize
        self.degrees = degrees
        let aspectRatio = imageSize.width / imageSize.height
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
        let radians = Float(degrees * .pi / 180.0)
        let rotatedX = tableX * cos(radians) - tableZ * sin(radians)
        let rotatedZ = tableX * sin(radians) + tableZ * cos(radians)
        return SIMD3<Float>(rotatedX, Self.pinHeight, rotatedZ)
    }

    /// Exact inverse of `tablePosition(for:)`, clamped to the image bounds.
    func mapLocation(for position: SIMD3<Float>) -> CGPoint {
        let radians = Float(-degrees * .pi / 180.0)
        let tableX = position.x * cos(radians) - position.z * sin(radians)
        let tableZ = position.x * sin(radians) + position.z * cos(radians)
        let x = (CGFloat(tableX / planeWidth) + 0.5) * imageSize.width
        let y = (CGFloat(tableZ / planeDepth) + 0.5) * imageSize.height
        return CGPoint(x: min(max(x, 0), imageSize.width), y: min(max(y, 0), imageSize.height))
    }
}

#endif
