// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import UIKit
import RPGTabletopGameContent
import os.log

@MainActor
class GameRenderer: TabletopGame.RenderDelegate {
    let cursorEntity: Entity
    let root: Entity
    // Initial fallback for the table height inside the app volume. The value
    // -0.7 assumes Apple's 1.5 m-tall sample volume (origin at volume center);
    // our volume is flatter, so the view corrects it via placeTable(bottomY:)
    // once RealityView reports the actual volume bounds.
    let rootOffset: Vector3D = .init(x: 0, y: -0.7, z: 0)
    weak var game: GameTableModel?
    private var didLoadAssets = false

    /// The GM-shared 3D object (SpaceRPG), floating above the board. Lives as
    /// a plain child of `root` — the same coordinate space and TabletopKit
    /// seating every other table entity uses — rather than in a separate
    /// `ImmersiveSpace`/RealityKit scene, so it appears exactly over the table
    /// for as long as this volumetric window is open. `SpaceViewer`'s own
    /// `ImmersiveSpace` remains the fallback for when it isn't (see
    /// `GameRootViewer`'s space `.onChange` handler).
    private var spaceObjectEntity: Entity?
    private var loadedSpaceObjectId: UUID?
    
    @MainActor
    init() {
        // Move everything down within the volume so the tabletop is easier to see.
        root = Entity()
        root.transform.translation = .init(rootOffset)

        // Create a cursor mesh to show when a player hovers over a tile or group.
        self.cursorEntity = ModelEntity.cursor
        self.cursorEntity.setParent(root)
        
        // Assets are loaded when GameTableView appears. Keeping this
        // initializer resource-free also supports lightweight control tests.
    }
    
    @MainActor
    func loadAssets() async {
        guard !didLoadAssets else { return }
        didLoadAssets = true

        do {
            let table = try await TableAssetFactory.makePlainWoodTable()
            table.setParent(root)
        } catch {
            Logger.gameTable.error(
                "Failed to load the plain wood table: \(error.localizedDescription, privacy: .public)"
            )
        }
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

    /// Applies a uniform scale to the complete table scene.
    func applyScale(_ scale: Float) {
        root.scale = SIMD3<Float>(repeating: scale)
    }

    /// Positions the table scene at the actual bottom of the volumetric window.
    /// RealityView's origin is the volume center and content outside the bounds
    /// is clipped, so a fixed offset only works for one specific volume height —
    /// the system may also clamp the requested window size.
    func placeTable(bottomY: Float) {
        root.transform.translation.y = bottomY
    }

    /// Removes the shared 3D object, if one is loaded. Called when the game
    /// master stops revealing a Space item.
    func clearSpaceObject() {
        spaceObjectEntity?.removeFromParent()
        spaceObjectEntity = nil
        loadedSpaceObjectId = nil
    }

    /// Loads a GM-shared 3D object and centers it above the board. Scaled
    /// smaller than `SpaceViewer`'s own immersive-space presentation (which
    /// fills a person's whole view) since this one shares the board with the
    /// map, pins, hands, and deck.
    func loadSpaceObject(itemId: UUID, from url: URL) async {
        guard loadedSpaceObjectId != itemId else { return }
        clearSpaceObject()

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let entity = try? await Entity(contentsOf: url, withName: "SharedSpaceObject"),
              entity.children.count > 0 || entity.components.count > 0 else {
            Logger.gameTable.error("Failed to load shared 3D object for the table")
            return
        }

        // Same world-space normalization `SpaceViewer.loadEntity` uses: undo
        // any embedded USDZ unit transform, then scale to a fixed footprint.
        let baseExtents = entity.visualBounds(relativeTo: nil).extents / entity.scale
        let maxBase = max(baseExtents.x, max(baseExtents.y, baseExtents.z))
        if maxBase > 0.0001, maxBase.isFinite {
            entity.scale = SIMD3<Float>(repeating: Self.spaceObjectTargetSize / maxBase)
        }

        let visualCenter = entity.visualBounds(relativeTo: nil).center
        entity.position = SIMD3(
            -visualCenter.x,
            MapTableProjection.pinHeight + Self.spaceObjectHeightAboveBoard - visualCenter.y,
            -visualCenter.z
        )
        root.addChild(entity)
        spaceObjectEntity = entity
        loadedSpaceObjectId = itemId
    }

    private static let spaceObjectTargetSize: Float = 0.3
    private static let spaceObjectHeightAboveBoard: Float = 0.3

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
