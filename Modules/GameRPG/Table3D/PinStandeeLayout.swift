// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

/// Pure geometry of a pin's photo standee (the upright cutout on the token base), kept free of
/// RealityKit so it can be unit-tested on iOS.
struct PinStandeeLayout: Equatable {
    /// Standee height limit, in token diameters.
    static let maximumHeightFactor: Float = 1.8
    /// Standee width limit, in token diameters. A wide creature may overhang the base a little.
    static let maximumWidthFactor: Float = 1.3
    /// Local Y of the standee's bottom edge: the top of the photo disc on the base.
    static let bottomY: Float = 0.004
    /// Half the gap between the two printed faces, so they never z-fight.
    static let faceOffset: Float = 0.0003
    /// Local Y of the lying (dead) standee, above the disc and below the death-mark bars.
    static let fallenY: Float = 0.0046
    /// Collision height of a token without a standee (and of a fallen one).
    static let flatCollisionHeight: Float = 0.02

    let width: Float
    let height: Float

    /// Fits a cutout of `aspect` (width / height) into the limits for a token of `diameter`.
    init(aspect: Float, diameter: Float) {
        let safeAspect = aspect.isFinite && aspect > 0 ? aspect : 1
        var height = diameter * Self.maximumHeightFactor
        var width = height * safeAspect
        let maximumWidth = diameter * Self.maximumWidthFactor
        if width > maximumWidth {
            width = maximumWidth
            height = width / safeAspect
        }
        self.width = width
        self.height = height
    }

    /// Hit-test box of an upright standee: covers the figure and the base.
    func collisionSize(diameter: Float) -> SIMD3<Float> {
        SIMD3(max(width, diameter), Self.bottomY + height, diameter)
    }

    /// Centre of `collisionSize`, so the box starts at the table surface.
    func collisionCenterY() -> Float {
        (Self.bottomY + height) / 2
    }

    /// Z shift of the root of a lying standee, which extends along -Z from its root: centres the
    /// figure on the base.
    var fallenRootZ: Float { height / 2 }
}
#endif
