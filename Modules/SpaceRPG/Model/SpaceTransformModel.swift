// @copyright André Trettin

import CoreRPG
import Foundation
import simd

/// The manipulation state of a 3D model in the shared immersive space.
///
/// Rotation is a quaternion, stored as four floats since `simd_quatf` itself
/// isn't `Codable` — not yaw/pitch: `ManipulationComponent`'s gestures (single-
/// and two-handed) produce arbitrary 3D rotations that a yaw/pitch pair can't
/// represent. Position and scale are local to the model's anchor, which is
/// identical on every participant's device (shared world origin during
/// SharePlay, same initial head-locked offset otherwise).
struct SpaceTransformModel: Codable, Equatable, Sendable, MessageMapper {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    var rotation: SIMD4<Float>
}

extension SpaceTransformModel {
    /// Largest position component or scale factor accepted from a peer.
    static let maximumMagnitude: Float = 1_000

    /// Whether a peer-supplied transform is safe to apply: finite everywhere, a non-zero scale
    /// within limits and a non-degenerate rotation. NaN/infinite or zero-length values would
    /// produce NaN transforms in the viewer. See CODE_AUDIT_16 §5.7.
    var isPlausible: Bool {
        let components = [position.x, position.y, position.z, scale.x, scale.y, scale.z,
                          rotation.x, rotation.y, rotation.z, rotation.w]
        guard components.allSatisfy(\.isFinite) else { return false }
        guard position.x.magnitude <= Self.maximumMagnitude,
              position.y.magnitude <= Self.maximumMagnitude,
              position.z.magnitude <= Self.maximumMagnitude else { return false }
        guard [scale.x, scale.y, scale.z].allSatisfy({ $0 > 0 && $0 <= Self.maximumMagnitude }) else { return false }
        let length = (rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z + rotation.w * rotation.w).squareRoot()
        return length > 0.001 && length.isFinite
    }

    init(position: SIMD3<Float>, scale: SIMD3<Float>, orientation: simd_quatf) {
        self.init(
            position: position,
            scale: scale,
            rotation: SIMD4(orientation.imag.x, orientation.imag.y, orientation.imag.z, orientation.real)
        )
    }

    var orientation: simd_quatf {
        simd_quatf(ix: rotation.x, iy: rotation.y, iz: rotation.z, r: rotation.w)
    }
}
