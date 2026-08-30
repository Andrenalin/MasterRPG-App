// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import Spatial
import RealityKit

extension Double {
   // The linear interpolation of a Double, from one given value to another, by a specified factor.
   static func lerp(lhs: Self, rhs: Self, factor: Self) -> Self {
       lhs + (rhs - lhs) * factor
   }
}

extension TableVisualState.Point2D {
    static func lerp(lhs: Self, rhs: Self, factor: Double) -> Self {
        .init(x: Double.lerp(lhs: lhs.x, rhs: rhs.x, factor: factor),
              z: Double.lerp(lhs: lhs.z, rhs: rhs.z, factor: factor))
    }
    
    static func + (lhs: TableVisualState.Point2D, rhs: TableVisualState.Point2D) -> TableVisualState.Point2D {
        return TableVisualState.Point2D(x: lhs.x + rhs.x, z: lhs.z + rhs.z)
    }
}

extension TableVisualState.Pose2D {
    static func lerp(lhs: Self, rhs: Self, factor: Double) -> Self {
        .init(position: TableVisualState.Point2D.lerp(lhs: lhs.position, rhs: rhs.position, factor: factor),
              rotation: Angle2D(radians: Double.lerp(lhs: lhs.rotation.radians, rhs: rhs.rotation.radians, factor: factor)))
    }
}

func transformPoint(pose: TableVisualState.Pose2D, point: TableVisualState.Point2D) -> TableVisualState.Point2D {
    let sinTheta = sin(pose.rotation)
    let cosTheta = cos(pose.rotation)
    let rotatedP = simd_double2(x: point.x * cosTheta + point.z * sinTheta,
                                y: point.x * -sinTheta + point.z * cosTheta)
    return TableVisualState.Point2D(x: rotatedP.x, z: rotatedP.y) + pose.position
}

extension TableVisualState.Pose2D {
    static func * (lhs: TableVisualState.Pose2D, rhs: TableVisualState.Pose2D) -> TableVisualState.Pose2D {
        let position = transformPoint(pose: rhs, point: lhs.position)
        let rotation = lhs.rotation + rhs.rotation
        return TableVisualState.Pose2D(position: position, rotation: rotation)
    }
}

extension simd_float4x4 {
    /// World-space translation extracted from the 4th column.
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension Pose3D {
    /// Converts a `TabletopInteraction.Value.pose` (Spatial's double-precision
    /// `Pose3D`) into a RealityKit `Transform`, via its underlying matrix — used to
    /// place content that lives outside TabletopKit's own automatic equipment
    /// rendering, currently only the drag-destination cursor. See CODE_AUDIT_9 §5.2.
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
