// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import RPGTabletopGameContent
import Spatial
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
    var pawns: [PlayerPawn] = []
    var seats: [PlayerSeat] = []

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

        loadEntityEquipment()
    }
    
    func loadEntityEquipment() {
        for (index, pawnInfo) in PlayerPawn.pawns.enumerated() {
            let pawn = PlayerPawn(id: PlayerPawn.ID(self.idGenerator.newId()),
                                  seat: seats[index],
                                  cuteBotColor: pawnInfo.1,
                                  entity: try! Entity.load(named: pawnInfo.0, in: tabletopGameContentBunlde))
            pawns.append(pawn)
            setup.add(equipment: pawn)
        }
    }
    
    /// Syncs player pawns on the 3D table with player pins from the 2D map
    /// - Parameters:
    ///   - mapModel: The map containing player pins
    ///   - mapImage: The current map image for aspect ratio calculations
    ///   - degrees: The rotation of the map
    func syncPlayerPawnsWithMapPins(mapModel: MapModel, mapImage: AKImage, degrees: Double) {
        // Get player pins from the map
        let playerPins = mapModel.mapPins.filter { $0.isPlayer && $0.isShown }
        
        guard !playerPins.isEmpty else {
            print("No visible player pins found on map")
            return
        }
        
        // Get map dimensions and aspect ratio
        guard let cgImage = mapImage.cgImage else {
            print("Failed to get image dimensions")
            return
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let aspectRatio = imageWidth / imageHeight
        
        // Calculate the actual rendered map size on the board (matching Board.updateMap logic)
        let mapSize = GameMetrics.tableEdge - (0.05 * 2) // 5cm border on all sides
        let planeWidth: Float
        let planeDepth: Float
        
        if aspectRatio > 1.0 {
            // Landscape - width constrained
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            // Portrait or square - height constrained
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
        }
        
        // Match each pawn with its corresponding pin
        for (pawnIndex, pawn) in pawns.enumerated() {
            // Try to find a matching pin for this pawn
            // Option 1: Match by index (first pawn matches first player pin, etc.)
            // Option 2: Match by seat assignment stored in pin.players
            
            // Using index-based matching for now
            guard pawnIndex < playerPins.count else {
                print("No pin available for pawn \(pawnIndex)")
                continue
            }
            
            let pin = playerPins[pawnIndex]
            
            // Convert 2D map coordinates to 3D table coordinates
            // Map coordinates are in pixels, table coordinates are in meters
            // The board is centered at (0, 0, 0) on the table
            
            // Normalize pin location to 0...1 range
            let normalizedX = pin.location.x / imageWidth
            let normalizedY = pin.location.y / imageHeight
            
            // Convert to table coordinates
            // X: -planeWidth/2 to +planeWidth/2
            // Z: -planeDepth/2 to +planeDepth/2
            let tableX = Float(normalizedX - 0.5) * planeWidth
            let tableZ = Float(normalizedY - 0.5) * planeDepth
            
            // Apply rotation if map is rotated
            let radians = Float(degrees * .pi / 180.0)
            let cosRad = cos(radians)
            let sinRad = sin(radians)
            let rotatedX = tableX * cosRad - tableZ * sinRad
            let rotatedZ = tableX * sinRad + tableZ * cosRad
            
            // Update the pawn's entity position directly
            // Since TabletopKit doesn't expose state update APIs outside interactions,
            // we manipulate the RealityKit entity transform directly
            let yPosition: Float = 0.03 // Position above the board surface
            pawn.entity.position = SIMD3<Float>(rotatedX, yPosition, rotatedZ)
            
            print("Syncing pawn \(pawnIndex) '\(pin.name)' to position (\(rotatedX), \(rotatedZ))")
        }
    }
}

extension GameTableModel {
    @MainActor
    func resetGame() {
        // Move pawns back to their starting location.
        for pawn in setup.pawns {
            // Reset entity position to match initial state
            let initialPose = pawn.initialState.pose
            let yPosition: Float = 0.03 // Position above the board surface
            pawn.entity.position = SIMD3<Float>(
                Float(initialPose.position.x),
                yPosition,
                Float(initialPose.position.z)
            )
        }
    }
    
    /// Syncs player pawns with player pins from the current map
    @MainActor
    func syncPawnsWithMapPins() {
        // Get the current map
        guard let mapId = currentMapId,
              let mapImage = currentMapImage else {
            print("No current map available to sync pawns")
            return
        }
        
        // Get the map model from mapRoot with proper type casting
        guard let mapModel = mapRoot.itemControllable.itemSync(for: mapId) as? MapModel else {
            print("Could not find map model for current map")
            return
        }
        
        // Sync pawns with map pins
        setup.syncPlayerPawnsWithMapPins(
            mapModel: mapModel,
            mapImage: mapImage,
            degrees: currentMapDegrees
        )
        
        print("✅ Synced pawns with map pins")
    }
}

#endif
