// @copyright André Trettin

import simd

/// Decides when the foreground over a spatial photo has to be placed again. Placing it reads the
/// photo's visual bounds, a traversal of the entity, and ran on every RealityKit frame (about 90
/// times a second) although nothing had moved. The inputs that move the foreground are cheap to
/// read, so the traversal only runs when one of them changed, and on every frame while the photo
/// is still converting (its depth grows then). See CODE_AUDIT_24 §7.1.
struct ForegroundPlacementGate {
    /// What the foreground's place depends on, apart from the photo's own depth.
    struct Inputs: Equatable {
        var windowCenter: SIMD3<Float>
        var windowExtents: SIMD3<Float>
        var photoScale: SIMD3<Float>
        var photoScreenSize: SIMD2<Float>
        /// The photo is not settled: its depth still changes without any other input moving.
        var isPhotoChanging: Bool
    }

    private var placedInputs: Inputs?

    /// Whether the foreground has to be placed for `inputs`. Records them as placed.
    mutating func needsPlacement(for inputs: Inputs) -> Bool {
        defer { placedInputs = inputs }
        return inputs.isPhotoChanging || inputs != placedInputs
    }

    /// Forgets what was placed, so the next frame places the foreground.
    mutating func reset() {
        placedInputs = nil
    }
}
