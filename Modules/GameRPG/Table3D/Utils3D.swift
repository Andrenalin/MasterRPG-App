// @copyright André Trettin

#if os(visionOS)
import Spatial
import RealityKit

extension simd_float4x4 {
    /// World-space translation extracted from the 4th column.
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension Pose3D {
    /// Converts a `TabletopInteraction.Value.pose` (Spatial's double-precision `Pose3D`) into a
    /// RealityKit `Transform`, via its underlying matrix — used to place content that lives outside
    /// TabletopKit's own automatic equipment rendering, currently only the drag-destination cursor.
    var cursorTransform: Transform {
        let m = matrix
        let singlePrecision = simd_float4x4(
            SIMD4<Float>(m.columns.0),
            SIMD4<Float>(m.columns.1),
            SIMD4<Float>(m.columns.2),
            SIMD4<Float>(m.columns.3)
        )
        return Transform(matrix: singlePrecision)
    }
}

#endif
