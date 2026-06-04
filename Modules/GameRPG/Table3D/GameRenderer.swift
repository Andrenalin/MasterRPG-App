// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import RPGTabletopGameContent

@MainActor
class GameRenderer: TabletopGame.RenderDelegate {
    let cursorEntity: Entity
    let root: Entity
    var cuteBots: [Entity] = []
    // The root offset controls the height of the table inside the app volume.
    let rootOffset: Vector3D = .init(x: 0, y: -0.7, z: 0)
    weak var game: GameTableModel?
    let portalWorld: Entity
    let portal: Entity
    
    @MainActor
    init() {
        // Move everything down within the volume so the tabletop is easier to see.
        root = Entity()
        root.transform.translation = .init(rootOffset)

        // Create a cursor mesh to show when a player hovers over a tile or group.
        self.cursorEntity = ModelEntity.cursor
        self.cursorEntity.setParent(root)
        
        portalWorld = Entity()
        portal = Entity()
        
        // Assets will be loaded explicitly by GameTableModel
    }
    
    @MainActor
    func loadAssets() async {
        #if DEBUG
        print("🎮 Loading TabletopGame assets...")
        #endif
        
        do {
            let staticSceneEntity = try await Entity(named: "static_scene", in: tabletopGameContentBunlde)
            staticSceneEntity.setParent(root)
            
            #if DEBUG
            print("✅ TabletopGame assets loaded successfully")
            print("   Root children: \(root.children.count)")
            print("   Static scene name: \(staticSceneEntity.name)")
            print("   Static scene children: \(staticSceneEntity.children.count)")
            
            // List all children for debugging
            for (index, child) in staticSceneEntity.children.enumerated() {
                print("     Child \(index): \(child.name) (type: \(type(of: child)))")
            }
            #endif
        } catch {
            print("❌ Failed to load static_scene: \(error)")
            print("   Continuing without static scene assets")
        }

        portalWorld.components.set(WorldComponent())
        portalWorld.transform.translation = .init(rootOffset)
        portalWorld.transform.translation.y += GameMetrics.tableThickness * 0.5
        let portalMesh = MeshResource.generateBox(width: 0.6, height: 0, depth: 0.6)
        let portalEntity = ModelEntity(mesh: portalMesh, materials: [PortalMaterial()])
        let portalComp = PortalComponent(
            target: portalWorld,
            clippingPlane: .init(position: .init(), normal: .init(x: 0, y: -1, z: 0))
        )
        portalEntity.components.set(portalComp)
        portalEntity.transform.translation = .init(rootOffset)
        portal.addChild(portalEntity)
    }
    
    @MainActor
    var cursorTransform: Transform? = nil {
        willSet(newValue) {
            if cursorTransform == newValue {
                return
            }

            if cursorTransform == nil, let newValue {
                // When the cursor turns on, snap to the supplied position.
                cursorEntity.transform = newValue
                cursorEntity.isEnabled = true
            } else if let newValue {
                // Animate while the cursor is on.
                cursorEntity.move(to: newValue, relativeTo: root, duration: 0.1, timingFunction: .easeInOut)
            } else if newValue == nil {
                // Turn the cursor off.
                cursorEntity.isEnabled = false
            }
        }
    }

    @MainActor
    func getAnimation(entity: Entity, animation: PlayerPawn.AnimationState) -> AnimationResource? {
        if let component = entity.components[AnimationLibraryComponent.self] {
            return component.animations[animation.rawValue]
        }
        return nil
    }
    
    @MainActor
    func playAnimation(entity: Entity, animation: AnimationResource) {
        if let rigGroup = entity.findEntity(named: "cutebot_bind") {
            rigGroup.playAnimation(animation, transitionDuration: 1, startsPaused: false)
        }
    }

    /// Applies a uniform scale to the table scene and the portal window.
    /// The portal world itself is not scaled (it is a coordinate space, not geometry).
    func applyScale(_ scale: Float) {
        let s = SIMD3<Float>(repeating: scale)
        root.scale   = s
        portal.scale = s
    }

    @MainActor
    func cuteBotEntity(for cuteBotColor: PlayerPawn.CuteBotColor) -> Entity {
        switch cuteBotColor {
        case .red:
            return cuteBots[0]
        case .blue:
            return cuteBots[1]
        case .purple:
            return cuteBots[2]
        }
    }
    
    nonisolated func updateCursor(_ proposedDestination: EquipmentIdentifier?, valid: Bool = false) {
        Task { @MainActor in
            guard let game = game else {
                return
            }
            game.renderer.cursorTransform = nil
        }
    }
}

extension ModelEntity {
    static var cursor: ModelEntity {
        let cursorMesh = MeshResource.generateCylinder(height: 0.01, radius: 0.02)
        let cursorEntity = ModelEntity(mesh: cursorMesh)
        cursorEntity.name = "cursor"
        cursorEntity.isEnabled = false
        var cursorMaterial = PhysicallyBasedMaterial()
        cursorMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .init(white: 0, alpha: 0.3))
        cursorMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 1)
        cursorMaterial.blending = .transparent(opacity: 0.6)
        cursorEntity.model!.materials.append(cursorMaterial)
        return cursorEntity
    }
}

#endif
