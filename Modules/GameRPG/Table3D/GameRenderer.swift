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
    /// Depth is a fixed constant, not a live read of the window bounds; it reads
    /// `GameTableView.volumeSize`, the single source of truth shared with `WindowVisionList`.
    private static var volumeDepth: Double { GameTableView.volumeSize.depth }
    /// How far back from the volume's front (+Z) face the table sits; see
    /// `GameTableView.frontClearance` for why it is 15 cm.
    private static var frontClearance: Double { GameTableView.frontClearance }
    // Y (-0.7) is only a fallback until `placeTable(bottomY:)` reports the real volume bounds.
    // Z is set once: `root`'s origin is the table's *center* (only Y is offset), so the front edge
    // sits `frontClearance` behind the volume's front face by subtracting both that clearance and
    // half the table's depth (`GameMetrics.tableLength / 2`) from the volume's half-depth. Leaving
    // out the half-depth pushed the table 0.75 m toward the viewer and clipped it.
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
        scaleDidChange?(scale)
    }

    /// Called with the new scale after every `applyScale(_:)`: the seat control panels cancel it.
    var scaleDidChange: ((Float) -> Void)?

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
