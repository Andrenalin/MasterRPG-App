// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The committed placement of the map canvas in viewport coordinates.
///
/// Gesture values are intentionally not stored here. A gesture captures one
/// absolute transform as its baseline, derives transient transforms from that
/// value, and commits the final transform when it ends.
struct MapViewportTransform: Equatable {
    static let minimumScale: CGFloat = 0.1

    let scale: CGFloat
    let offset: CGPoint

    init(scale: CGFloat, offset: CGPoint) {
        self.scale = scale
        self.offset = offset
    }

    /// Returns a transform that keeps the same canvas point below `anchor`.
    /// `magnification` is the cumulative value reported by `MagnifyGesture`.
    func magnified(
        by magnification: CGFloat,
        around anchor: CGPoint,
        minimumScale: CGFloat = Self.minimumScale
    ) -> Self {
        guard scale.isFinite,
              scale > 0,
              magnification.isFinite,
              magnification > 0 else { return self }

        let newScale = max(minimumScale, scale * magnification)
        let appliedMagnification = newScale / scale
        let newOffset = CGPoint(
            x: anchor.x + (offset.x - anchor.x) * appliedMagnification,
            y: anchor.y + (offset.y - anchor.y) * appliedMagnification
        )
        return Self(scale: newScale, offset: newOffset)
    }

    func translated(by translation: CGSize) -> Self {
        guard translation.width.isFinite, translation.height.isFinite else { return self }
        return Self(
            scale: scale,
            offset: CGPoint(
                x: offset.x + translation.width,
                y: offset.y + translation.height
            )
        )
    }
}

@MainActor @Observable
final class ImageViewerModel {
    init(offset: CGPoint = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.lastOffset = offset
        self.scale = scale
        self.lastScale = scale
        normScale = scale
    }

    var offset: CGPoint
    var lastOffset: CGPoint
    var scale: CGFloat
    var lastScale: CGFloat

    var normScale: CGFloat

    var viewportTransform: MapViewportTransform {
        MapViewportTransform(scale: scale, offset: offset)
    }
}
