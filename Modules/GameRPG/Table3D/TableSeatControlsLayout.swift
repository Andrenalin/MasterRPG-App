// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

/// Where the control panels of a seat stand on the table: on the seat's own edge, at the map's
/// start and end, turned to the seated player and sloped toward their eyes. Pure
/// geometry in table meters, free of RealityKit so it can be unit-tested on iOS.
///
/// "Leading" is the seated player's left, "trailing" their right, exactly as the dice row is laid
/// out (`TableSeatDice.positions`: the first die is the leftmost for the player).
struct TableSeatControlsLayout: Equatable {
    enum Side: Sendable {
        case leading, trailing

        /// Which way along the seat's lateral axis (to the player's right) the side lies.
        fileprivate var sign: Double {
            switch self {
            case .leading: -1
            case .trailing: 1
            }
        }
    }

    /// Slope of a panel from the vertical, toward the player's eyes.
    static let tilt: Float = .pi / 4
    /// Distance of a panel's bottom edge from the table's rim, so it stands where the dice do.
    static let edgeInset: Double = 0.03
    /// Room kept free between a panel and the table's corner.
    static let cornerClearance: Double = 0.02

    /// The bottom-centre of the panel on the table plane (Y is the board surface), its yaw about
    /// the vertical axis (the seat's facing: +Z of the panel points at the seated player) and the
    /// slope.
    struct Placement: Equatable {
        let position: SIMD3<Float>
        let yaw: Float
        let pitch: Float

        /// The panel's orientation: yaw to the seat, then leaning back by `pitch` about its own
        /// bottom edge so its face looks up at the player.
        var orientation: simd_quatf {
            simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: -pitch, axis: SIMD3<Float>(1, 0, 0))
        }
    }

    /// The table's half length along a seat's edge: what lies between its two corners.
    static func edgeHalfLength(rotation radians: Double) -> Double {
        // The edge runs along the lateral axis: X for the end seats (facing along Z), Z for the
        // side seats.
        abs(sin(radians)) * Double(GameMetrics.tableLength / 2) + abs(cos(radians)) * Double(GameMetrics.tableWidth / 2)
    }

    /// The seat's lateral coordinate of one end of the map along the seat's edge, as the seated
    /// player sees it, for a map of `planeWidth` x `planeDepth` centred on the table: the leading
    /// side is the player's left (negative), the trailing side their right.
    static func mapEdge(
        _ side: Side,
        rotation radians: Double,
        planeWidth: Double,
        planeDepth: Double
    ) -> Double {
        side.sign * (abs(cos(radians)) * planeWidth / 2 + abs(sin(radians)) * planeDepth / 2)
    }

    /// A panel whose `side` edge stands at `edgeLateral` along the seat's edge — a leading panel
    /// starts there and reaches inward, a trailing one ends there — and which rises
    /// `stackedAbove` up the slope, in table meters, to stand on top of another panel. The panels
    /// stand where the map starts and ends.
    static func edgeAlignedPlacement(
        side: Side,
        rotation radians: Double,
        edgeLateral: Double,
        width: Double,
        stackedAbove: Double = 0,
        surfaceY: Float = GameMetrics.tableThickness
    ) -> Placement {
        let direction: (x: Double, z: Double) = (sin(radians), cos(radians))
        let lateral: (x: Double, z: Double) = (direction.z, -direction.x)
        let halfExtent = abs(direction.x) * Double(GameMetrics.tableWidth / 2)
            + abs(direction.z) * Double(GameMetrics.tableLength / 2)
        // The panel stays between the table's corners.
        let limit = max(0, edgeHalfLength(rotation: radians) - cornerClearance - width / 2)
        let centre = min(max(edgeLateral - side.sign * width / 2, -limit), limit)
        return standing(
            direction: direction, lateral: lateral, radius: halfExtent - edgeInset, centre: centre,
            radians: radians, stackedAbove: stackedAbove, surfaceY: surfaceY
        )
    }

    private static func standing(
        direction: (x: Double, z: Double),
        lateral: (x: Double, z: Double),
        radius: Double,
        centre: Double,
        radians: Double,
        stackedAbove: Double,
        surfaceY: Float
    ) -> Placement {
        let base = SIMD3<Float>(
            Float(direction.x * radius + lateral.x * centre),
            surfaceY,
            Float(direction.z * radius + lateral.z * centre)
        )
        let placement = Placement(position: base, yaw: Float(radians), pitch: tilt)
        guard stackedAbove > 0 else { return placement }
        // Up the slope, so the upper panel continues the lower one's plane.
        let up = placement.orientation.act(SIMD3<Float>(0, Float(stackedAbove), 0))
        return Placement(position: base + up, yaw: placement.yaw, pitch: placement.pitch)
    }
}
#endif
