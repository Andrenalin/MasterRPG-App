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
    var monsterPawns: [MonsterPawn] = [] // Track monster pawns dynamically
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
        
        // Get map dimensions and calculate positions
        guard let cgImage = mapImage.cgImage else {
            print("Failed to get image dimensions")
            return
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let aspectRatio = imageWidth / imageHeight
        
        // Calculate the actual rendered map size on the board
        let mapSize = GameMetrics.tableEdge - (0.05 * 2) // 5cm border on all sides
        let planeWidth: Float
        let planeDepth: Float
        
        if aspectRatio > 1.0 {
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
        }
        
        // Sync player pawns
        for (pawnIndex, pawn) in pawns.enumerated() {
            guard pawnIndex < playerPins.count else {
                print("No pin available for pawn \(pawnIndex)")
                continue
            }
            
            let pin = playerPins[pawnIndex]
            let position = calculateTablePosition(
                pinLocation: pin.location,
                imageSize: CGSize(width: imageWidth, height: imageHeight),
                planeWidth: planeWidth,
                planeDepth: planeDepth,
                degrees: degrees
            )
            
            pawn.entity.position = position
            print("Syncing player pawn \(pawnIndex) '\(pin.name)' to position (\(position.x), \(position.z))")
        }
    }
    
    /// Syncs monster pawns on the 3D table with monster pins from the 2D map
    /// Dynamically creates, updates, and removes monster pawns as needed
    /// - Parameters:
    ///   - mapModel: The map containing monster pins
    ///   - mapImage: The current map image for aspect ratio calculations
    ///   - degrees: The rotation of the map
    func syncMonsterPawnsWithMapPins(mapModel: MapModel, mapImage: AKImage, degrees: Double) {
        // Get monster pins from the map (not player pins, and shown)
        let monsterPins = mapModel.mapPins.filter { !$0.isPlayer && $0.isShown }
        
        print("🐉 Syncing \(monsterPins.count) monster pins")
        
        // Get map dimensions
        guard let cgImage = mapImage.cgImage else {
            print("Failed to get image dimensions")
            return
        }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let aspectRatio = imageWidth / imageHeight
        
        // Calculate the actual rendered map size on the board
        let mapSize = GameMetrics.tableEdge - (0.05 * 2)
        let planeWidth: Float
        let planeDepth: Float
        
        if aspectRatio > 1.0 {
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
        }
        
        // Track which monster pawns to keep
        //let monsterPinIds = Set(monsterPins.map { $0.id })
        
        // Update existing monster pawns or hide them if pin no longer exists
        for monsterPawn in monsterPawns {
            if let pin = monsterPins.first(where: { $0.id == monsterPawn.pinId }) {
                // Update existing pawn
                let position = calculateTablePosition(
                    pinLocation: pin.location,
                    imageSize: CGSize(width: imageWidth, height: imageHeight),
                    planeWidth: planeWidth,
                    planeDepth: planeDepth,
                    degrees: degrees
                )
                
                var updatedPawn = monsterPawn
                updatedPawn.update(position: position, color: pin.color, size: pin.size)
                
                // Make sure entity is visible
                updatedPawn.entity.isEnabled = true
                
                print("🔄 Updated monster '\(pin.name)' at (\(position.x), \(position.z))")
            } else {
                // Pin no longer exists, hide the entity instead of removing
                monsterPawn.entity.isEnabled = false
                print("👻 Hidden monster pawn (pin no longer exists)")
            }
        }
        
        // Create new monster pawns for new pins
        let existingPinIds = Set(monsterPawns.map { $0.pinId })
        let newPins = monsterPins.filter { !existingPinIds.contains($0.id) }
        
        for pin in newPins {
            let position = calculateTablePosition(
                pinLocation: pin.location,
                imageSize: CGSize(width: imageWidth, height: imageHeight),
                planeWidth: planeWidth,
                planeDepth: planeDepth,
                degrees: degrees
            )
            
            let monsterPawn = MonsterPawn(
                id: EquipmentIdentifier(idGenerator.newId()),
                pinId: pin.id,
                position: position,
                color: pin.color,
                size: pin.size
            )
            
            monsterPawns.append(monsterPawn)
            setup.add(equipment: monsterPawn)
            
            print("✨ Created new monster '\(pin.name)' at (\(position.x), \(position.z))")
        }
        
        // Count visible monsters
        let visibleCount = monsterPawns.filter { $0.entity.isEnabled }.count
        print("🐉 Monster sync complete: \(visibleCount) visible monsters (total: \(monsterPawns.count))")
    }
    
    /// Helper function to calculate 3D table position from 2D map coordinates
    /// - Parameters:
    ///   - pinLocation: The pin location in pixel coordinates
    ///   - imageSize: The size of the map image
    ///   - planeWidth: The rendered width of the map on the table
    ///   - planeDepth: The rendered depth of the map on the table
    ///   - degrees: The rotation of the map
    /// - Returns: 3D position on the table
    private func calculateTablePosition(
        pinLocation: CGPoint,
        imageSize: CGSize,
        planeWidth: Float,
        planeDepth: Float,
        degrees: Double
    ) -> SIMD3<Float> {
        // Normalize pin location to 0...1 range
        let normalizedX = pinLocation.x / imageSize.width
        let normalizedY = pinLocation.y / imageSize.height
        
        // Convert to table coordinates
        let tableX = Float(normalizedX - 0.5) * planeWidth
        let tableZ = Float(normalizedY - 0.5) * planeDepth
        
        // Apply rotation
        let radians = Float(degrees * .pi / 180.0)
        let cosRad = cos(radians)
        let sinRad = sin(radians)
        let rotatedX = tableX * cosRad - tableZ * sinRad
        let rotatedZ = tableX * sinRad + tableZ * cosRad
        
        // Position above the board surface
        let yPosition: Float = 0.03
        
        return SIMD3<Float>(rotatedX, yPosition, rotatedZ)
    }
    
    /// Clears all monster pawns (hides all and clears the array)
    /// Use this when changing maps or completely resetting the game
    func clearAllMonsters() {
        for monsterPawn in monsterPawns {
            monsterPawn.entity.isEnabled = false
        }
        monsterPawns.removeAll()
        print("🧹 Cleared all monster pawns")
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
        
        // Hide all monster pawns on reset (they remain in array for potential reuse)
        for monsterPawn in setup.monsterPawns {
            monsterPawn.entity.isEnabled = false
        }
        print("🔄 Game reset: hidden all monster pawns")
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
        
        // Sync player pawns with map pins
        setup.syncPlayerPawnsWithMapPins(
            mapModel: mapModel,
            mapImage: mapImage,
            degrees: currentMapDegrees
        )
        
        // Sync monster pawns with map pins
        setup.syncMonsterPawnsWithMapPins(
            mapModel: mapModel,
            mapImage: mapImage,
            degrees: currentMapDegrees
        )
        
        print("✅ Synced pawns and monsters with map pins")
    }
    
    /// Syncs only monster pawns (useful for GM operations)
    @MainActor
    func syncMonsterPawns() {
        guard let mapId = currentMapId,
              let mapImage = currentMapImage else {
            print("No current map available to sync monsters")
            return
        }
        
        guard let mapModel = mapRoot.itemControllable.itemSync(for: mapId) as? MapModel else {
            print("Could not find map model for current map")
            return
        }
        
        setup.syncMonsterPawnsWithMapPins(
            mapModel: mapModel,
            mapImage: mapImage,
            degrees: currentMapDegrees
        )
        
        print("✅ Synced \(setup.monsterPawns.count) monster pawns")
    }
    
    /// Clears all monsters from the table
    /// Useful when changing maps or starting fresh
    @MainActor
    func clearAllMonsters() {
        setup.clearAllMonsters()
    }
}

#endif
