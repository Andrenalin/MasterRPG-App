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
    /// How far back from the volume's actual front (near-viewer, +Z) face
    /// `positionInitialDepth(volumeBounds:)` sets the table, so it doesn't
    /// sit right at the near clipping bound, uncomfortably close to the
    /// viewer, when this window opens. `WindowVisionList`'s
    /// `.defaultSize(depth:)` carries this much extra room beyond the
    /// table's own footprint, specifically so it opens in front of the
    /// table instead of pushing the table's far edge past the volume's
    /// back bound.
    private static let frontStandoff: Float = 0.5
    /// Set once `positionInitialDepth(volumeBounds:)` has placed the table's
    /// Z — guards against re-deriving it on every `RealityView` update pass.
    /// Y (`placeTable(bottomY:)`) is safe to recompute continuously (that's
    /// the proven, original behavior); doing the same for Z made the table's
    /// depth placement visibly shift on interaction instead of staying put,
    /// since — unlike Y — it had never been live-recomputed before. See
    /// `positionInitialDepth(volumeBounds:)`.
    private var hasPositionedInitialDepth = false
    weak var game: GameTableModel?
    private var didLoadAssets = false

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
    /// the system may also clamp the requested window size. Safe to call on every
    /// `RealityView` content/update pass — this has always been recomputed live
    /// (see `GameTableView`) without issue.
    func placeTable(bottomY: Float) {
        root.transform.translation.y = bottomY
    }

    /// Positions the table `Self.frontStandoff` back from the volume's actual
    /// front (near-viewer, +Z) face — once, the first time this is called after
    /// the table appears, then never again. Call this only from `RealityView`'s
    /// `content:` (init) closure, not `update:`: unlike `placeTable(bottomY:)`,
    /// re-deriving this on every update pass (including ones triggered by the
    /// person interacting with/dragging the window) made the table's depth
    /// placement visibly change instead of staying put — see
    /// `hasPositionedInitialDepth`'s own doc.
    func positionInitialDepth(volumeBounds: BoundingBox) {
        guard !hasPositionedInitialDepth else { return }
        hasPositionedInitialDepth = true
        root.transform.translation.z = volumeBounds.max.z - Self.frontStandoff
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
        cursorEntity.model?.materials.append(cursorMaterial)
        return cursorEntity
    }
}

#endif
