// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import TabletopKit
import RealityKit
import SwiftUI
import UIKit
import RPGTabletopGameContent
import os.log

@MainActor
final class GameRenderer: TabletopGame.RenderDelegate {
    let cursorEntity: Entity
    let root: Entity
    /// Marks the center of the table's top surface (`TableAssetFactory
    /// .makePlainWoodTable()` rests the slab's bottom on `root`'s origin).
    /// Registered as `SpaceRootModel.tablePlacementReference` so the
    /// immersive `SpaceViewer` can float SharePlay-shared objects above the
    /// table — see that property's doc.
    let tableTopEntity: Entity
    /// Not read from the window at runtime — see `rootOffset`'s own doc for
    /// why depth specifically stays static. Reads `GameTableView.volumeSize`
    /// (the single source of truth also feeding `WindowVisionList`'s
    /// `.defaultSize(...)`) rather than duplicating its own copy of the same
    /// figure — see `GameTableView.frontClearance`'s own doc for the
    /// specific math.
    private static var volumeDepth: Double { GameTableView.volumeSize.depth }
    /// How far back from the volume's front (near-viewer, +Z) face the table
    /// sits. Tightened from an earlier ~0.5 m held here for viewer comfort
    /// so the window's system grab handle and this view's
    /// `.bottomFront` ornament — both
    /// anchored to that same front face — sit close to the table's own
    /// front edge instead of a visible gap; 15 cm rather than 1 cm (which
    /// `sideClearance` uses on X) because — confirmed on-device — the master
    /// seat's own tossed dice overshoot their resting position mid-toss, and
    /// 1/5/10 cm all let that overshoot clip through the volume's front
    /// bound. Reads `GameTableView.frontClearance` rather than its own
    /// duplicate literal — see that property's own doc.
    private static var frontClearance: Double { GameTableView.frontClearance }
    // Y (-0.7) is only an initial fallback, good until `placeTable(bottomY:)`
    // reports the actual volume bounds — -0.7 assumes Apple's 1.5 m-tall
    // sample volume (origin at volume center); our volume is flatter.
    //
    // Z, unlike Y, is set here once and for good — see `frontClearance`'s
    // own doc for why depth stays a fixed constant rather than a live read.
    // `root`'s own local origin is the *center* of the wood table, not its
    // front edge: `TableAssetFactory.makePlainWoodTable()` generates it as a
    // box centered on its own origin, only ever offsetting Y (to rest its
    // bottom at the floor), never X/Z. So placing the table's front edge
    // `frontClearance` behind the volume's front (near-viewer, +Z) face means
    // subtracting *both* that clearance *and* half the table's own depth
    // (`GameMetrics.tableLength / 2` — the table's long axis is Z now, see
    // `PlayerSeat.seatPoses`'s own doc) from the volume's own half-depth —
    // an earlier version of this omitted the table's own half-depth
    // entirely, which pushed the whole table (and, past its own front edge,
    // the near-edge seat's dice) 0.75 m too far toward the viewer — enough
    // to clip past the volume's front bound and disappear. With `frontClearance`
    // now only 15 cm, that same omission would clip almost immediately.
    let rootOffset: Vector3D = .init(
        x: 0,
        y: -0.7,
        z: volumeDepth / 2 - frontClearance - Double(GameMetrics.tableLength) / 2
    )
    weak var game: GameTableModel?
    private var didLoadAssets = false
    private var isLoadingAssets = false

    init() {
        // Move everything down within the volume so the tabletop is easier to see.
        root = Entity()
        root.transform.translation = .init(rootOffset)

        tableTopEntity = Entity()
        tableTopEntity.name = "TableTop"
        tableTopEntity.position.y = GameMetrics.tableThickness
        tableTopEntity.setParent(root)

        // Create a cursor mesh to show when a player hovers over a tile or group.
        self.cursorEntity = ModelEntity.cursor
        self.cursorEntity.setParent(root)
        
        // Assets are loaded when GameTableView appears. Keeping this
        // initializer resource-free also supports lightweight control tests.
    }
    
    /// Loads the table mesh. A failure is logged and can be retried by calling again; only a
    /// successful load (or one already in flight) makes later calls no-ops.
    func loadAssets() async {
        guard !didLoadAssets, !isLoadingAssets else { return }
        isLoadingAssets = true
        defer { isLoadingAssets = false }

        do {
            let table = try await TableAssetFactory.makePlainWoodTable()
            table.setParent(root)
            didLoadAssets = true
        } catch {
            Logger.gameTable.error(
                "Failed to load the plain wood table: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)"
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

    /// TabletopKit's per-frame callback, with the state it is about to draw: the only place that
    /// sees whether a die is still travelling to where its state puts it.
    func onUpdate(timeInterval: Double, snapshot: TableSnapshot, visualState: TableVisualState) {
        game?.updateDiceResults(snapshot: snapshot, visualState: visualState)
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
    /// `@MainActor`, so no actor hop is needed here.
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
