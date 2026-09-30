// @copyright André Trettin

import Foundation
import Observation
import simd

/// Where the 3D object floats above the volumetric game table, and whether a space realignment
/// may re-place it. Split out of `SpaceViewer`, so the decision and the pose math are testable
/// without RealityKit. See CODE_AUDIT_19 §9.23.
@MainActor @Observable
final class SpaceTablePlacement {
    /// Height (meters) of the object's visual center above the game-table top.
    nonisolated static let heightAboveTable: Float = 1.0

    /// The game-table top (`SpaceRootModel.tablePlacementReference`'s entity id) the object was
    /// last floated above.
    private(set) var tableId: UInt64?
    /// Set once anyone moves the object after it was floated above the table, so a later space
    /// realignment doesn't throw that pose away.
    private(set) var isMovedSinceTablePlacement = false

    /// A realignment re-places the object unless someone moved it since it was placed on this table.
    func shouldPlace(onTable tableId: UInt64) -> Bool {
        !(self.tableId == tableId && isMovedSinceTablePlacement)
    }

    func didPlace(onTable tableId: UInt64) {
        self.tableId = tableId
        isMovedSinceTablePlacement = false
    }

    /// The object already has a synced pose: treat it as placed and moved, so opening it keeps
    /// where someone left it.
    func adoptRetainedPose(onTable tableId: UInt64?) {
        self.tableId = tableId
        isMovedSinceTablePlacement = true
    }

    func markMoved() {
        isMovedSinceTablePlacement = true
    }

    /// The offset that moves the object's visual center `heightAboveTable` above the table top.
    /// `tableTop` and `anchorPose` are in the immersive space, `objectCenter` in the anchor's.
    nonisolated static func objectOffset(
        tableTop: simd_float4x4,
        anchorPose: simd_float4x4,
        objectCenter: SIMD3<Float>
    ) -> SIMD3<Float> {
        let target = tableTop.columns.3 + SIMD4<Float>(0, heightAboveTable, 0, 0)
        let targetInAnchor = anchorPose.inverse * target
        return SIMD3(targetInAnchor.x, targetInAnchor.y, targetInAnchor.z) - objectCenter
    }
}
