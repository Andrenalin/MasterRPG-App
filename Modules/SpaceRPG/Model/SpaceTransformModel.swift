// @copyright André Trettin

import CoreRPG
import Foundation
import simd

/// The manipulation state of a 3D model in the shared immersive space.
///
/// Rotation is expressed as yaw/pitch (not a quaternion) because SpaceViewer
/// derives the entity rotation from these values; position and scale are local
/// to the model's anchor, which is identical on every participant's device
/// (shared world origin during SharePlay, same initial head-locked offset otherwise).
struct SpaceTransformModel: Codable, Equatable, Sendable, MessageMapper {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    var yaw: Float
    var pitch: Float
}
