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
