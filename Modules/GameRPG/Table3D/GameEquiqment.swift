// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import RPGTabletopGameContent
import Spatial

extension EquipmentIdentifier {
    static var tableID: Self { .init(0) }
}

struct Table: Tabletop {
    var shape: TabletopShape = .rectangular(width: GameMetrics.tableEdge, height: GameMetrics.tableEdge, thickness: 0)
    
    var id: EquipmentIdentifier = .tableID
}

struct Board: Equipment {
    let id: ID

    var initialState: BaseEquipmentState {
        .init(parentID: .tableID,
              seatControl: .restricted([]),
              pose: .init(position: .init(), rotation: .degrees(45)),
              boundingBox: .init(center: .zero, size: .init(GameMetrics.boardEdge, GameMetrics.boardHeight, GameMetrics.boardEdge)))
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
        // The die asset's default orientation shows 6 on top (+y), 2 on the right (+x), and 3 on the front (+z).
        switch state.value {
            case 20: // Flip upside down.
                return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
            case 14: // Flip to the left once.
                return .init(angle: .init(degrees: +180 + 41.811), axis: .init(x: 1, y: 0, z: 1))
            case 3: // Flip to the back once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
            case 4: // Flip to the front once.
                return .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
            case 5: // Flip to the right once.
                return .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
            case 6: // Default orientation.
                return .init()
        case 7: // Flip upside down.
            return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
        case 8: // Flip to the left once.
            return .init(angle: .init(degrees: +90), axis: .init(x: 0, y: 0, z: 1))
        case 9: // Flip to the back once.
            return .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
        case 10: // Flip to the front once.
            return .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
        case 11: // Flip to the right once.
            return .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
        case 12: // Default orientation.
            return .init()

        case 13: // Flip upside down.
            return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
        case 2: // Flip to the left once.
            return .init(angle: .init(degrees: +90), axis: .init(x: 0, y: 0, z: 1))
        case 15: // Flip to the back once.
            return .init(angle: .init(degrees: -90), axis: .init(x: 1, y: 0, z: 0))
        case 16: // Flip to the front once.
            return .init(angle: .init(degrees: +90), axis: .init(x: 1, y: 0, z: 0))
        case 17: // Flip to the right once.
            return .init(angle: .init(degrees: -90), axis: .init(x: 0, y: 0, z: 1))
        case 18: // Default orientation.
            return .init()

        case 19: // Flip upside down.
            return .init(angle: .init(degrees: +180), axis: .init(x: 0, y: 0, z: 1))
        case 1: // Flip to the left once.
            return .init(angle: .init(degrees: +0), axis: .init(x: 0, y: 0, z: 1))

        default:
            fatalError("Invalid die value")
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
