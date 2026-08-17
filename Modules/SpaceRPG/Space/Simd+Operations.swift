// @copyright André Trettin

import simd

extension SIMD3<Float> {
    static var upward: SIMD3<Float> {
        SIMD3<Float>(0, 1, 0)
    }

    static var left: SIMD3<Float> {
        SIMD3<Float>(1, 0, 0)
    }
}
