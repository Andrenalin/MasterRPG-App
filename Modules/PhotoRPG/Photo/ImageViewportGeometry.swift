// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

struct ImageViewportConfiguration: Equatable, Sendable {
    init(id: UUID, imageSize: CGSize, containerSize: CGSize, degrees: Double) {
        self.id = id
        self.imageSize = imageSize.validViewportSize
        self.containerSize = containerSize.validViewportSize
        self.degrees = ViewportGeometry.normalize(rotationDegrees: degrees)
    }

    let id: UUID
    let imageSize: CGSize
    let containerSize: CGSize
    let degrees: Double
}

typealias ImageViewport = ViewportTransform

/// Photo-specific rotation and fill calculations layered on the shared CoreRPG viewport engine.
struct ImageViewportGeometry: Sendable {
    init(configuration: ImageViewportConfiguration) {
        self.configuration = configuration
    }

    let configuration: ImageViewportConfiguration

    var originalImageSize: CGSize {
        configuration.imageSize
    }

    var containerSize: CGSize {
        configuration.containerSize
    }

    var normalizedDegrees: Double {
        configuration.degrees
    }

    var rotatedImageSize: CGSize {
        ViewportGeometry.rotatedContentSize(
            originalImageSize,
            rotationDegrees: normalizedDegrees
        )
    }

    var viewportConfiguration: ViewportConfiguration {
        // ImageViewer historically allowed zooming to at least native 1× resolution. Preserve
        // that behavior while maps can use the shared engine's exact 8×-fit default.
        let baseConfiguration = ViewportConfiguration(
            id: configuration.id,
            contentSize: rotatedImageSize,
            containerSize: containerSize,
            maximumScaleMultiplier: Self.maximumScaleMultiplier,
            panPolicy: .contained
        )
        let baseGeometry = ViewportGeometry(configuration: baseConfiguration)
        let desiredMaximumScale = max(baseGeometry.maximumScale, 1)
        let multiplier = desiredMaximumScale / baseGeometry.fitScale
        return ViewportConfiguration(
            id: configuration.id,
            contentSize: rotatedImageSize,
            containerSize: containerSize,
            maximumScaleMultiplier: multiplier.isFinite ? multiplier : Self.maximumScaleMultiplier,
            panPolicy: .contained
        )
    }

    var viewportGeometry: ViewportGeometry {
        ViewportGeometry(configuration: viewportConfiguration)
    }

    var fitScale: CGFloat {
        viewportGeometry.fitScale
    }

    var maximumScale: CGFloat {
        viewportGeometry.maximumScale
    }

    var fitViewport: ImageViewport {
        viewportGeometry.fitTransform
    }

    var fillScale: CGFloat {
        ViewportGeometry.fillScale(
            contentSize: originalImageSize,
            containerSize: containerSize,
            rotationDegrees: normalizedDegrees
        )
    }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        viewportGeometry.clampedScale(scale)
    }

    func clampedOffset(_ offset: CGPoint, at scale: CGFloat) -> CGPoint {
        viewportGeometry.clampedOffset(offset, at: scale)
    }

    func zoomedViewport(
        from viewport: ImageViewport,
        toScale proposedScale: CGFloat,
        anchor: CGPoint
    ) -> ImageViewport {
        viewportGeometry.zoomed(from: viewport, toScale: proposedScale, anchor: anchor)
    }

    func doubleTapViewport(from viewport: ImageViewport, at location: CGPoint) -> ImageViewport {
        viewportGeometry.doubleTapped(from: viewport, at: location)
    }

    static func normalize(_ degrees: Double) -> Double {
        ViewportGeometry.normalize(rotationDegrees: degrees)
    }
}

private extension ImageViewportGeometry {
    static let maximumScaleMultiplier: CGFloat = 8
}
