// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

// Loupe placement math lives in MapOverlayLoupeGeometry.swift, and the shared
// CGRect helpers in MapOverlayGeometryHelpers.swift — split out of this file.
// See CODE_AUDIT §9.13.

/// Pure needle-drag conversion. Gesture locations are expressed in viewport
/// space while persisted room coordinates live in logical map space.
enum MapNeedleDragGeometry {
    static func coordinate(
        originalCoordinate: CGPoint,
        startViewportPoint: CGPoint,
        currentViewportPoint: CGPoint,
        viewportGeometry: ViewportGeometry,
        transform: ViewportTransform
    ) -> CGPoint {
        let start = viewportGeometry.contentPoint(
            fromViewport: startViewportPoint,
            transform: transform
        )
        let current = viewportGeometry.contentPoint(
            fromViewport: currentViewportPoint,
            transform: transform
        )
        return CGPoint(
            x: originalCoordinate.x + current.x - start.x,
            y: originalCoordinate.y + current.y - start.y
        )
    }
}
