// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import TabletopKit
import RealityKit
import RPGTabletopGameContent
import Spatial
import DeveloperToolsSupport
import SwiftUI
import UIKit

extension EquipmentIdentifier {
    static var tableID: Self { .init(0) }
}

struct Table: Tabletop {
    var shape: TabletopShape = .rectangular(width: GameMetrics.tableEdge, height: GameMetrics.tableEdge, thickness: 0)
    
    var id: EquipmentIdentifier = .tableID
}

struct Board: EntityEquipment {
    let id: ID
    let entity: Entity
    var initialState: BaseEquipmentState
    
    // Store the image plane as a property so we can update it
    private let imagePlane: ModelEntity
    private let mapSize: Float
    
    @MainActor
    init(id: ID) {
        self.id = id
        
        // 5cm border on all sides
        let borderSize: Float = 0.05
        self.mapSize = GameMetrics.tableEdge - (borderSize * 2)
        let boxHeight: Float = 0.02  // 2cm height
        
        // Create the board entity
        let boardEntity = Entity()
        
        // Create base board mesh (3D box) with 2cm height
        let boardMesh = MeshResource.generateBox(
            width: GameMetrics.boardEdge,
            height: boxHeight,
            depth: GameMetrics.boardEdge
        )
        
        var boardMaterial = PhysicallyBasedMaterial()
        boardMaterial.baseColor = .init(tint: UIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0))
        let boardModel = ModelEntity(mesh: boardMesh, materials: [boardMaterial])
        boardEntity.addChild(boardModel)
        
        // Create image plane on top of the board
        let plane = ModelEntity(
            mesh: .generatePlane(width: mapSize, depth: mapSize),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        
        // Position the image plane on top of the 2cm box
        plane.position.y = boxHeight / 2 + 0.001
        plane.name = "MapImagePlane"  // Name it for easy finding
        
        // Load and apply the map texture
        var mapMaterial = UnlitMaterial()
        // Fallback to a green grid pattern on init (later we see the map here)
        mapMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1.0))
        plane.model?.materials = [mapMaterial]
        
        boardEntity.addChild(plane)
        self.imagePlane = plane
        
        self.entity = boardEntity
        
        // Align with table (no rotation)
        self.initialState = .init(
            parentID: .tableID,
            seatControl: .restricted([]),
            pose: .init(position: .init(), rotation: .degrees(0)),
            entity: self.entity
        )
    }
        
    // Method to update map from PhotoModel data
    @MainActor func updateMap(image: AKImage, degrees: Double) {
        guard let cgImage = image.cgImage else {
            print("Failed to create image from photo data")
            return
        }
        
        var mapMaterial = UnlitMaterial()
        do {
            let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
            mapMaterial.color = .init(texture: .init(texture))
        } catch {
            print("Failed to generate texture from photo: \(error)")
            mapMaterial.color = .init(tint: .gray)
        }
        imagePlane.model?.materials = [mapMaterial]
    }
}

struct PlayerSeat: TableSeat {
    let id: ID
    var initialState: TableSeatState

    /* There are three seats around the edges of the table.
    Each seat faces the center of the table. */
    @MainActor static let seatPoses: [TableVisualState.Pose2D] = [
        .init(position: .init(x: 0, z: Double(GameMetrics.tableEdge)), rotation: .degrees(0)),
        .init(position: .init(x: -Double(GameMetrics.tableEdge), z: 0), rotation: .degrees(-90)),
        .init(position: .init(x: Double(GameMetrics.tableEdge), z: 0), rotation: .degrees(90))
    ]
    
    init(id: TableSeatIdentifier, pose: TableVisualState.Pose2D) {
        self.id = id
        let spatialSeatPose: TableVisualState.Pose2D = .init(position: pose.position,
                                                             rotation: pose.rotation)
        initialState = .init(pose: spatialSeatPose)
    }
}

struct PlayerPawn: EntityEquipment {
    public enum AnimationState: String, Codable, Sendable, Equatable, CaseIterable {
        case idleA
        case jumpJoy
        case sad
    }

    enum CuteBotColor: Sendable {
        case red
        case purple
        case blue
    }

    let id: ID
    let cuteBotColor: CuteBotColor
    let entity: Entity

    var initialState: BaseEquipmentState
    
    static let pawns: [(String, CuteBotColor)] = [
        ("player_pawn_red_assembly", .red),
        ("player_pawn_purple_assembly", .purple),
        ("player_pawn_blue_assembly", .blue)
    ]

    @MainActor
    init(id: ID, seat: PlayerSeat, cuteBotColor: CuteBotColor, entity: Entity) {
        self.id = id
        self.cuteBotColor = cuteBotColor
        self.entity = entity
        let pawnToSeat: TableVisualState.Pose2D = .init(position: .init(x: -0.2, z: -0.3), rotation: .init())
        let seatToTable = seat.initialState.pose
        let pawnToTable = pawnToSeat * seatToTable
        initialState = .init(parentID: .tableID, pose: pawnToTable, entity: self.entity)
    }
}

struct Die20: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController
    var initialState: DieState
    let representation: TossableRepresentation
    
    // Return the orientation of the die entity to a given value face up.
    func restingOrientation(state: DieState) -> Rotation3D {
        // D20 model - faces arranged on an icosahedron
        // Testing shows: 1 is default up, 20 is opposite (bottom)
        // The remaining faces need to be determined by testing the actual 3D model
        print("**** Rolled: \(state.value)")
        switch state.value {
            case 1: // Default orientation - 1 facing up
                return .init(angle: .init(degrees: 180), axis: .init(x: 1, y: 0, z: 0))
        case 2:
        return .init(angle: .init(degrees: 63.4), axis: .init(x: 0.809, y: 0, z: 0.588))

            case 7:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: 1, y: 0, z: 0))
        case 9:
            return .init(angle: .init(degrees: 116.6), axis: .init(x: -0.809, y: 0, z: -0.588))
        case 10:
            return .init(angle: .init(degrees: 63.4), axis: .init(x: 0.809, y: 0, z: -0.588))
        case 14:
            return .init(angle: .init(degrees: 63.4), axis: .init(x: -1, y: 0, z: 0))

            case 18:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: -0.309, y: 0, z: 0.951))

        case 20: // Opposite of 1 - flip 180°
            //return .init(angle: .init(degrees: 180), axis: .init(x: 1, y: 0, z: 0))
            return .init()

            
            // Adjacent to 1 (first ring of 5 faces around 1)
            // Tilt ~63.4° (icosahedron dihedral complement)
            case 12: 
                return .init(angle: .init(degrees: 63.4), axis: .init(x: 1, y: 0, z: 0))
            case 3:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: 0.309, y: 0, z: 0.951))
            case 4:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: -0.809, y: 0, z: 0.588))
            case 5:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: -0.809, y: 0, z: -0.588))
            case 6:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: 0.309, y: 0, z: -0.951))
                
            // Second ring (offset ring) - tilt ~63.4° on different axes
            case 8:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: -0.309, y: 0, z: 0.951))
            case 11:
                return .init(angle: .init(degrees: 63.4), axis: .init(x: -0.309, y: 0, z: -0.951))
                
            // Third ring - larger tilt ~116.6° (icosahedron dihedral angle)
            case 13:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: 0.309, y: 0, z: 0.951))
            case 15:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: -0.809, y: 0, z: 0.588))
            case 16:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: 0.309, y: 0, z: -0.951))
                
            // Ring adjacent to 20 (near bottom)
            case 17:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: 0.809, y: 0, z: 0.588))
            case 19:
                return .init(angle: .init(degrees: 116.6), axis: .init(x: -1, y: 0, z: 0))
                
            default:
                fatalError("Invalid die value: \(state.value). D20 must have value 1-20")
        }
    }
    
    @MainActor
    init(id: ID) {
        self.id = id
        self.entity = try! Entity.load(named: "D20Blue", in: tabletopGameContentBunlde)
        self.entity.scale.x = 0.00025
        self.entity.scale.y = 0.00025
        self.entity.scale.z = 0.00025
        let audioResource = try! AudioFileResource.load(named: "/Root/dieSoundShort_mp3",
                                                        from: "static_scene.usda",
                                                        in: tabletopGameContentBunlde)
        self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        representation = .icosahedron(height: entity.visualBounds(relativeTo: nil).extents.x)
            //.dodecahedron(height: entity.visualBounds(relativeTo: nil).extents.x)
        let pose: TableVisualState.Pose2D = .init(position: .init(x: -0.2, z: -0.5), rotation: .zero)
        initialState = .init(value: 1, parentID: .tableID, seatControl: .any, pose: pose, entity: self.entity)
    }

    @MainActor
    func playTossSound() {
        if !audioPlaybackController.isPlaying {
            audioPlaybackController.seek(to: .zero)
            audioPlaybackController.play()
        }
    }
}

struct Die: EntityEquipment {
    let id: ID
    let entity: Entity
    let audioPlaybackController: AudioPlaybackController
    var initialState: DieState
    let representation: TossableRepresentation
    
    // Return the orientation of the die entity to a given value face up.
    func restingOrientation(state: DieState) -> Rotation3D {
        // The die asset's default orientation shows 6 on top (+y), 2 on the right (+x), and 3 on the front (+z).
        switch state.value {
            case 1: // Flip upside down.
                return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
            case 2: // Flip to the left once.
                return .init(angle: .init(degrees: +90), axis: .init(x: 0, y: 0, z: 1))
            case 3: // Flip to the back once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
            case 4: // Flip to the front once.
                return .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
            case 5: // Flip to the right once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
            case 6: // Default orientation.
                return .init()
            default:
            fatalError("Invalid die value")
        }
    }
    
    @MainActor
    init(id: ID) {
        self.id = id
        self.entity = try! Entity.load(named: "Die", in: tabletopGameContentBunlde)
        let audioResource = try! AudioFileResource.load(named: "/Root/dieSoundShort_mp3",
                                                        from: "static_scene.usda",
                                                        in: tabletopGameContentBunlde)
        self.audioPlaybackController = self.entity.prepareAudio(audioResource)
        representation = .cube(height: entity.visualBounds(relativeTo: nil).extents.x)
        let pose: TableVisualState.Pose2D = .init(position: .init(x: -0.3, z: -0.5), rotation: .zero)
        initialState = .init(value: 1, parentID: .tableID, seatControl: .any, pose: pose, entity: self.entity)
    }

    @MainActor
    func playTossSound() {
        if !audioPlaybackController.isPlaying {
            audioPlaybackController.seek(to: .zero)
            audioPlaybackController.play()
        }
    }
}

#endif
