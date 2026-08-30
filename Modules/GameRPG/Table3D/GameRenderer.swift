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
    /// Must match `WindowVisionList`'s `.defaultSize(depth:)`. Kept as a
    /// hardcoded constant, not read from the window at runtime — see
    /// `rootOffset`'s own doc for why depth specifically stays static now.
    /// 2.65 m (grown from an earlier 2.15 m) — the table's long dimension
    /// moved from X onto Z (see `PlayerSeat.seatPoses`'s own doc for why),
    /// so the volume's depth needed to grow to keep fitting it; see
    /// `frontStandoff`'s own doc for the specific math.
    private static let volumeDepth: Double = 2.65
    /// How far back from the volume's front (near-viewer, +Z) face the table
    /// sits, so it doesn't land right at the near clipping bound,
    /// uncomfortably close to the viewer, when this window opens. Held fixed
    /// across the `volumeDepth` growth from 2.15 to 2.65 m so the table's
    /// near edge — and the master's own seat and dice, which sit right at
    /// it — stays exactly where it already was; only the *far* end (now
    /// holding the table's long axis, plus the sixth, North seat) reaches
    /// further into the room. `WindowVisionList`'s `.defaultSize(depth:)`
    /// carries this much extra room beyond the table's own footprint,
    /// specifically so it opens in front of the table instead of pushing
    /// the table's far edge past the volume's back bound.
    private static let frontStandoff: Double = 0.5
    // Y (-0.7) is only an initial fallback, good until `placeTable(bottomY:)`
    // reports the actual volume bounds — -0.7 assumes Apple's 1.5 m-tall
    // sample volume (origin at volume center); our volume is flatter.
    //
    // Z, unlike Y, is set here once and for good — see `frontStandoff`'s own
    // doc for why depth stays a fixed constant rather than a live read.
    // `root`'s own local origin is the *center* of the wood table, not its
    // front edge: `TableAssetFactory.makePlainWoodTable()` generates it as a
    // box centered on its own origin, only ever offsetting Y (to rest its
    // bottom at the floor), never X/Z. So placing the table's front edge
    // `frontStandoff` behind the volume's front (near-viewer, +Z) face means
    // subtracting *both* that standoff *and* half the table's own depth
    // (`GameMetrics.tableLength / 2` — the table's long axis is Z now, see
    // `PlayerSeat.seatPoses`'s own doc) from the volume's own half-depth —
    // an earlier version of this omitted the table's own half-depth
    // entirely, which pushed the whole table (and, past its own front edge,
    // the near-edge seat's dice) 0.75 m too far toward the viewer — enough
    // to clip past the volume's front bound and disappear. With the new,
    // longer Z-extent this same mistake would clip by a full meter instead.
    let rootOffset: Vector3D = .init(
        x: 0,
        y: -0.7,
        z: volumeDepth / 2 - frontStandoff - Double(GameMetrics.tableLength) / 2
    )
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
    /// `RealityView` content/update pass — unlike Z (see `rootOffset`'s own doc),
    /// this has always been recomputed live without issue.
    func placeTable(bottomY: Float) {
        root.transform.translation.y = bottomY
    }

    /// Sets (or clears) the drag-destination cursor's transform directly — called
    /// from `GameInteraction.update(interaction:)`, which is itself already
    /// `@MainActor`, so no actor hop is needed here. See CODE_AUDIT_9 §5.2.
    func updateCursor(_ transform: Transform?) {
        cursorTransform = transform
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
