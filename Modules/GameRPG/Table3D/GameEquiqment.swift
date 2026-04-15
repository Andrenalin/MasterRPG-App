// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import MapRPG
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
    
    // Store the image plane and border as properties so we can update them
    private let imagePlane: ModelEntity
    private let borderPlane: ModelEntity
    private let fogContainer: Entity
    private let mapSize: Float
    private let boxHeight: Float = 0.02
    
    // Store current image dimensions for coordinate conversion
    private var currentImageWidth: CGFloat = 1
    private var currentImageHeight: CGFloat = 1
    
    @MainActor
    init(id: ID) {
        self.id = id
        
        // 5cm border on all sides
        let borderSize: Float = 0.05
        self.mapSize = GameMetrics.tableEdge - (borderSize * 2)
        
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
        
        // Create border plane (full size, behind the image)
        let border = ModelEntity(
            mesh: .generatePlane(width: mapSize, depth: mapSize),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        border.position.y = boxHeight / 2 + 0.0005
        border.name = "MapBorderPlane"
        boardEntity.addChild(border)
        self.borderPlane = border
        
        // Create image plane on top of the border (will be sized to aspect ratio)
        let plane = ModelEntity(
            mesh: .generatePlane(width: mapSize, depth: mapSize),
            materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )
        
        // Position the image plane on top of the border
        plane.position.y = boxHeight / 2 + 0.001
        plane.name = "MapImagePlane"
        
        // Fallback to a green grid pattern on init
        var mapMaterial = UnlitMaterial()
        mapMaterial.color = .init(tint: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1.0))
        plane.model?.materials = [mapMaterial]
        
        boardEntity.addChild(plane)
        self.imagePlane = plane
        
        // Create fog of war container on top of the image
        let fog = Entity()
        fog.name = "FogContainer"
        fog.position.y = boxHeight / 2 + 0.002  // Higher above the image
        boardEntity.addChild(fog)
        self.fogContainer = fog
        
        self.entity = boardEntity
        
        // Align with table (no rotation)
        self.initialState = .init(
            parentID: .tableID,
            seatControl: .restricted([]),
            pose: .init(position: .init(), rotation: .degrees(0)),
            entity: self.entity
        )
    }
        
    // Method to update map from PhotoModel data with aspect ratio and border color
    @MainActor mutating func updateMap(image: AKImage, degrees: Double, displayConfig: DisplayConfigModel?, mapModel: MapModel?) {
        guard let cgImage = image.cgImage else {
            print("Failed to create image from photo data")
            return
        }
        
        // Calculate aspect ratio and resize image plane
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let aspectRatio = imageWidth / imageHeight
        
        var planeWidth: Float
        var planeDepth: Float
        
        if aspectRatio > 1.0 {
            // Landscape - width constrained
            planeWidth = mapSize
            planeDepth = mapSize / Float(aspectRatio)
        } else {
            // Portrait or square - height constrained
            planeDepth = mapSize
            planeWidth = mapSize * Float(aspectRatio)
        }
        
        // Store current image dimensions for fog coordinate conversion
        if let mapModel = mapModel {
            currentImageWidth = mapModel.width
            currentImageHeight = mapModel.height
        }
        
        // Update image plane mesh with correct aspect ratio
        imagePlane.model?.mesh = .generatePlane(width: planeWidth, depth: planeDepth)
        
        // Update the texture using new visionOS 2.0+ API
        do {
            let texture = try TextureResource(image: cgImage, options: .init(semantic: .color))
            var mapMaterial = UnlitMaterial()
            mapMaterial.color = .init(texture: .init(texture))
            imagePlane.model?.materials = [mapMaterial]
        } catch {
            print("Failed to create texture from image: \(error)")
            var mapMaterial = UnlitMaterial()
            mapMaterial.color = .init(tint: .gray)
            imagePlane.model?.materials = [mapMaterial]
        }
        
        // Update border color from DisplayConfigModel
        if let displayConfig = displayConfig {
            let uiColor = UIColor(displayConfig.color)
            borderPlane.model?.materials = [SimpleMaterial(color: uiColor, isMetallic: false)]
        }
        
        // Update fog of war overlays
        if let mapModel = mapModel {
            updateFogOfWar(entries: mapModel.entries, imageWidth: planeWidth, imageHeight: planeDepth)
        }
    }
    
    // Update fog of war based on hidden map entries
    @MainActor private func updateFogOfWar(entries: [MapEntryModel], imageWidth: Float, imageHeight: Float) {
        print("🌫️ updateFogOfWar called with \(entries.count) total entries")
        print("🌫️ Image dimensions - width: \(currentImageWidth), height: \(currentImageHeight)")
        print("🌫️ Plane dimensions - width: \(imageWidth), depth: \(imageHeight)")
        
        // Clear existing fog overlays
        fogContainer.children.removeAll()
        print("🌫️ Cleared existing fog overlays")
        
        // Filter to only hidden entries (not shown to players)
        let hiddenEntries = entries.filter { !$0.isShown }
        print("🌫️ Found \(hiddenEntries.count) hidden entries")
        
        guard !hiddenEntries.isEmpty else {
            print("🌫️ No hidden areas - fog of war cleared")
            return
        }
        
        // Create fog overlay for each hidden entry
        var createdCount = 0
        for (index, entry) in hiddenEntries.enumerated() {
            print("🌫️ Processing entry \(index): '\(entry.name)' with \(entry.coordinates.count) coordinates")
            
            guard !entry.coordinates.isEmpty else {
                print("🌫️   Skipping - no coordinates")
                continue
            }
            
            // Convert coordinates to 3D mesh positions
            let vertices = entry.coordinates.map { coord -> SIMD3<Float> in
                convertCoordinate(coord, imageWidth: imageWidth, imageHeight: imageHeight)
            }
            
            print("🌫️   Vertices: \(vertices)")
            
            // Create a polygon mesh from the coordinates
            if let (fogMesh, centerOffset) = createPolygonMesh(from: vertices) {
                var fogMaterial = SimpleMaterial()
                fogMaterial.color = .init(tint: UIColor(red: 0, green: 0, blue: 0, alpha: 0.8))
                fogMaterial.triangleFillMode = .fill  // Ensure triangles are filled
                
                let fogEntity = ModelEntity(mesh: fogMesh, materials: [fogMaterial])
                fogEntity.name = "FogOverlay_\(entry.id)"
                
                // Position the entity at its center offset
                fogEntity.position = SIMD3<Float>(centerOffset.x, 0.0001 * Float(index), centerOffset.y)
                
                fogContainer.addChild(fogEntity)
                createdCount += 1
                print("🌫️   ✅ Created fog overlay for '\(entry.name)' at position: \(fogEntity.position)")
                print("🌫️       Entity bounds: \(fogEntity.visualBounds(relativeTo: fogContainer))")
            } else {
                print("🌫️   ❌ Failed to create mesh for '\(entry.name)'")
            }
        }
        
        print("🌫️ Fog of war complete: \(createdCount)/\(hiddenEntries.count) overlays created")
        print("🌫️ Fog container now has \(fogContainer.children.count) children")
    }
    
    // Convert 2D map coordinate to 3D position on the plane
    private func convertCoordinate(_ coord: CGPoint, imageWidth: Float, imageHeight: Float) -> SIMD3<Float> {
        // Normalize coordinates from image space (0...width, 0...height) to plane space (-width/2...width/2)
        let normalizedX = Float(coord.x / currentImageWidth)
        let normalizedY = Float(coord.y / currentImageHeight)
        
        // Convert to plane coordinates (centered at origin)
        let x = (normalizedX - 0.5) * imageWidth
        let z = (normalizedY - 0.5) * imageHeight
        
        return SIMD3<Float>(x, 0, z)
    }
    
    // Create a polygon mesh from vertices - creates a solid 3D box
    // Returns tuple of (mesh, centerOffset) where centerOffset is the XZ position to place the entity
    @MainActor private func createPolygonMesh(from vertices: [SIMD3<Float>]) -> (MeshResource, SIMD2<Float>)? {
        guard vertices.count >= 3 else {
            print("🌫️   Mesh creation failed: need at least 3 vertices, got \(vertices.count)")
            return nil
        }
        
        print("🌫️   Creating mesh from \(vertices.count) vertices")
        
        // For rectangular areas (4 vertices), use a simpler box approach
        if vertices.count == 4 {
            // Calculate bounding box
            let minX = vertices.map { $0.x }.min() ?? 0
            let maxX = vertices.map { $0.x }.max() ?? 0
            let minZ = vertices.map { $0.z }.min() ?? 0
            let maxZ = vertices.map { $0.z }.max() ?? 0
            
            let width = maxX - minX
            let depth = maxZ - minZ
            let height: Float = 0.11
            
            let centerX = (minX + maxX) / 2
            let centerZ = (minZ + maxZ) / 2
            
            print("🌫️   Rectangle detected - using box generator")
            print("🌫️   Box: width=\(width), height=\(height), depth=\(depth)")
            print("🌫️   Center will be positioned at: x=\(centerX), z=\(centerZ)")
            
            let mesh = MeshResource.generateBox(width: width, height: height, depth: depth)
            print("🌫️   ✅ Box mesh generated successfully")
            return (mesh, SIMD2<Float>(centerX, centerZ))
        }
        
        // For non-rectangular polygons, use extrusion (centered at origin, return center)
        let fogHeight: Float = 0.11
        let bottomY: Float = -0.01
        let topY: Float = 0.10
        
        // Calculate center for positioning
        let centerX = vertices.map { $0.x }.reduce(0, +) / Float(vertices.count)
        let centerZ = vertices.map { $0.z }.reduce(0, +) / Float(vertices.count)
        
        // Offset vertices to be centered at origin
        let centeredVertices = vertices.map { SIMD3<Float>($0.x - centerX, 0, $0.z - centerZ) }
        
        print("🌫️   Polygon detected - using extrusion (bottom: \(bottomY), top: \(topY))")
        print("🌫️   Center will be positioned at: x=\(centerX), z=\(centerZ)")
        
        var allVertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        
        // Bottom vertices
        let bottomVertices = centeredVertices.map { SIMD3<Float>($0.x, bottomY, $0.z) }
        allVertices.append(contentsOf: bottomVertices)
        
        // Top vertices
        let topVertices = centeredVertices.map { SIMD3<Float>($0.x, topY, $0.z) }
        allVertices.append(contentsOf: topVertices)
        
        // UVs
        for i in 0..<centeredVertices.count {
            let u = Float(i) / Float(centeredVertices.count)
            uvs.append(SIMD2<Float>(u, 0))
        }
        for i in 0..<centeredVertices.count {
            let u = Float(i) / Float(centeredVertices.count)
            uvs.append(SIMD2<Float>(u, 1))
        }
        
        let vertexCount = centeredVertices.count
        let bottomOffset: UInt32 = 0
        let topOffset: UInt32 = UInt32(vertexCount)
        
        // Bottom face (triangulated, facing down)
        for i in 1..<(vertexCount - 1) {
            indices.append(bottomOffset)
            indices.append(bottomOffset + UInt32(i + 1))
            indices.append(bottomOffset + UInt32(i))
        }
        
        // Top face (triangulated, facing up)
        for i in 1..<(vertexCount - 1) {
            indices.append(topOffset)
            indices.append(topOffset + UInt32(i))
            indices.append(topOffset + UInt32(i + 1))
        }
        
        // Side faces
        for i in 0..<vertexCount {
            let nextI = (i + 1) % vertexCount
            
            indices.append(bottomOffset + UInt32(i))
            indices.append(bottomOffset + UInt32(nextI))
            indices.append(topOffset + UInt32(i))
            
            indices.append(topOffset + UInt32(i))
            indices.append(bottomOffset + UInt32(nextI))
            indices.append(topOffset + UInt32(nextI))
        }
        
        // Normals
        for _ in bottomVertices {
            normals.append(SIMD3<Float>(0, -1, 0))
        }
        for _ in topVertices {
            normals.append(SIMD3<Float>(0, 1, 0))
        }
        
        print("🌫️   Total vertices: \(allVertices.count), indices: \(indices.count) (\(indices.count/3) triangles)")
        
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(allVertices)
        meshDescriptor.primitives = .triangles(indices)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            print("🌫️   ✅ Extruded mesh generated successfully")
            return (mesh, SIMD2<Float>(centerX, centerZ))
        } catch {
            print("🌫️   ❌ Mesh generation error: \(error)")
            return nil
        }
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
