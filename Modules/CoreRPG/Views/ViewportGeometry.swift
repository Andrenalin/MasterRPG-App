// @copyright André Trettin

import CoreGraphics
import Foundation
import Observation

/// Pure layout and coordinate-conversion functions shared by image and map viewers.
public struct ViewportGeometry: Sendable {
    public init(configuration: ViewportConfiguration) {
        self.configuration = configuration
    }

    public let configuration: ViewportConfiguration

    public var contentSize: CGSize {
        configuration.contentSize
    }

    public var containerSize: CGSize {
        configuration.containerSize
    }

    public var containerCenter: CGPoint {
        guard containerSize.isValidViewportSize else {
            return .zero
        }
        return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    public var fitScale: CGFloat {
        guard contentSize.isValidViewportSize, containerSize.isValidViewportSize else {
            return 1
        }

        let widthScale = containerSize.width / contentSize.width
        let heightScale = containerSize.height / contentSize.height
        let scale = min(widthScale, heightScale)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    public var maximumScale: CGFloat {
        guard fitScale <= .greatestFiniteMagnitude / configuration.maximumScaleMultiplier else {
            return .greatestFiniteMagnitude
        }
        return max(fitScale, fitScale * configuration.maximumScaleMultiplier)
    }

    public var fitTransform: ViewportTransform {
        ViewportTransform(scale: fitScale, offset: centeredOffset(at: fitScale))
    }

    public func contentSize(at scale: CGFloat) -> CGSize {
        guard contentSize.isValidViewportSize,
              scale.isFinite,
              scale > 0,
              contentSize.width <= .greatestFiniteMagnitude / scale,
              contentSize.height <= .greatestFiniteMagnitude / scale else {
            return .zero
        }

        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
            .validViewportSize
    }

    public func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else {
            return fitScale
        }
        return min(max(scale, fitScale), maximumScale)
    }

    public func clampedOffset(_ offset: CGPoint, at scale: CGFloat) -> CGPoint {
        let scale = clampedScale(scale)
        let transformedSize = contentSize(at: scale)
        guard transformedSize.isValidViewportSize,
              containerSize.isValidViewportSize,
              offset.isFinite else {
            return centeredOffset(at: scale)
        }

        return CGPoint(
            x: clampedAxisOffset(
                offset.x,
                contentLength: transformedSize.width,
                containerLength: containerSize.width
            ),
            y: clampedAxisOffset(
                offset.y,
                contentLength: transformedSize.height,
                containerLength: containerSize.height
            )
        )
    }

    public func constrained(_ transform: ViewportTransform) -> ViewportTransform {
        let scale = clampedScale(transform.scale)
        return ViewportTransform(scale: scale, offset: clampedOffset(transform.offset, at: scale))
    }

    public func zoomed(
        from transform: ViewportTransform,
        toScale proposedScale: CGFloat,
        anchor: CGPoint
    ) -> ViewportTransform {
        guard contentSize.isValidViewportSize, containerSize.isValidViewportSize else {
            return fitTransform
        }

        let baseline = constrained(transform)
        let newScale = clampedScale(proposedScale)
        let anchor = safeAnchor(anchor)
        let logicalPoint = contentPoint(fromViewport: anchor, transform: baseline)
        let proposedOffset = CGPoint(
            x: anchor.x - logicalPoint.x * newScale,
            y: anchor.y - logicalPoint.y * newScale
        )
        return constrained(ViewportTransform(scale: newScale, offset: proposedOffset))
    }

    public func magnified(
        from transform: ViewportTransform,
        magnification: CGFloat,
        anchor: CGPoint
    ) -> ViewportTransform {
        let baseline = constrained(transform)
        guard magnification.isFinite, magnification > 0 else {
            return baseline
        }
        let proposedScale = safelyMultiplied(baseline.scale, by: magnification)
        return zoomed(from: baseline, toScale: proposedScale, anchor: anchor)
    }

    /// Produces one transform from an immutable gesture baseline so simultaneous pan and pinch
    /// cannot overwrite one another.
    public func interacting(
        from baseline: ViewportTransform,
        translation: CGSize,
        magnification: CGFloat,
        anchor: CGPoint
    ) -> ViewportTransform {
        let magnified = magnified(from: baseline, magnification: magnification, anchor: anchor)
        guard translation.isFinite else {
            return magnified
        }
        return constrained(
            ViewportTransform(
                scale: magnified.scale,
                offset: CGPoint(
                    x: magnified.offset.x + translation.width,
                    y: magnified.offset.y + translation.height
                )
            )
        )
    }

    public func doubleTapped(from transform: ViewportTransform, at location: CGPoint) -> ViewportTransform {
        let baseline = constrained(transform)
        guard isAtFit(baseline) else {
            return fitTransform
        }

        let anchor = clampedToVisibleContent(location, transform: baseline)
        return magnified(
            from: baseline,
            magnification: Self.doubleTapScaleMultiplier,
            anchor: anchor
        )
    }

    public func contentPoint(fromViewport point: CGPoint, transform: ViewportTransform) -> CGPoint {
        let transform = constrained(transform)
        guard point.isFinite, transform.scale.isFinite, transform.scale > 0 else {
            return .zero
        }
        let result = CGPoint(
            x: (point.x - transform.offset.x) / transform.scale,
            y: (point.y - transform.offset.y) / transform.scale
        )
        return result.isFinite ? result : .zero
    }

    public func viewportPoint(fromContent point: CGPoint, transform: ViewportTransform) -> CGPoint {
        let transform = constrained(transform)
        guard point.isFinite,
              point.x.magnitude <= .greatestFiniteMagnitude / transform.scale,
              point.y.magnitude <= .greatestFiniteMagnitude / transform.scale else {
            return .zero
        }
        let result = CGPoint(
            x: point.x * transform.scale + transform.offset.x,
            y: point.y * transform.scale + transform.offset.y
        )
        return result.isFinite ? result : .zero
    }

    public func isAtFit(_ transform: ViewportTransform, tolerance: CGFloat = 0.0001) -> Bool {
        guard tolerance.isFinite, tolerance >= 0 else {
            return transform.scale == fitScale
        }
        let effectiveTolerance = max(tolerance, abs(fitScale) * tolerance)
        return transform.scale.isFinite && abs(transform.scale - fitScale) <= effectiveTolerance
    }

    /// Preserves the logical point under the old anchor when the container changes. A transform
    /// at fit is recentered at the new fit instead.
    public func resizedTransform(
        from transform: ViewportTransform,
        previousConfiguration: ViewportConfiguration,
        oldAnchor: CGPoint? = nil,
        newAnchor: CGPoint? = nil,
        refitWhenAtFit: Bool = true
    ) -> ViewportTransform {
        let previousGeometry = ViewportGeometry(configuration: previousConfiguration)
        guard previousConfiguration.id == configuration.id else {
            return fitTransform
        }

        let baseline = previousGeometry.constrained(transform)
        if refitWhenAtFit && previousGeometry.isAtFit(baseline) {
            return fitTransform
        }

        let oldAnchor = previousGeometry.safeAnchor(oldAnchor ?? previousGeometry.containerCenter)
        let newAnchor = safeAnchor(newAnchor ?? containerCenter)
        let logicalPoint = previousGeometry.contentPoint(fromViewport: oldAnchor, transform: baseline)
        let scale = clampedScale(baseline.scale)
        let offset = CGPoint(
            x: newAnchor.x - logicalPoint.x * scale,
            y: newAnchor.y - logicalPoint.y * scale
        )
        return constrained(ViewportTransform(scale: scale, offset: offset))
    }

    public static func normalize(rotationDegrees: Double) -> Double {
        guard rotationDegrees.isFinite else {
            return 0
        }

        let remainder = rotationDegrees.truncatingRemainder(dividingBy: 360)
        let normalized = remainder < 0 ? remainder + 360 : remainder
        return abs(normalized) < Double.ulpOfOne * 360 ? 0 : normalized
    }

    /// Sine and cosine of a rotation, exact for right-angle multiples instead of relying on
    /// `sin`/`cos` of `.pi`-derived radians, which leave a tiny (~1e-14) residual at 90°/270°
    /// that then propagates into "exact" sizes and coordinates like a 100pt canvas width.
    private static func sineCosine(rotationDegrees: Double) -> (sine: CGFloat, cosine: CGFloat) {
        let normalized = normalize(rotationDegrees: rotationDegrees)
        switch normalized {
        case 0: return (0, 1)
        case 90: return (1, 0)
        case 180: return (0, -1)
        case 270: return (-1, 0)
        default:
            let radians = normalized * .pi / 180
            return (CGFloat(sin(radians)), CGFloat(cos(radians)))
        }
    }

    public static func rotatedContentSize(_ contentSize: CGSize, rotationDegrees: Double) -> CGSize {
        guard contentSize.isValidViewportSize else {
            return .zero
        }

        let (sine, cosine) = sineCosine(rotationDegrees: rotationDegrees)
        let absCosine = abs(cosine)
        let absSine = abs(sine)
        let width = contentSize.width * absCosine + contentSize.height * absSine
        let height = contentSize.width * absSine + contentSize.height * absCosine
        return CGSize(width: width, height: height).validViewportSize
    }

    /// Converts an unrotated logical point into the top-leading coordinate space of its rotated
    /// bounding box. This uses the same center-based transform as SwiftUI's `rotationEffect`.
    public static func rotatedPoint(
        fromContent point: CGPoint,
        contentSize: CGSize,
        rotationDegrees: Double
    ) -> CGPoint {
        let rotatedSize = rotatedContentSize(contentSize, rotationDegrees: rotationDegrees)
        guard point.isFinite, contentSize.isValidViewportSize, rotatedSize.isValidViewportSize else {
            return .zero
        }

        let (sine, cosine) = sineCosine(rotationDegrees: rotationDegrees)
        let centered = CGPoint(
            x: point.x - contentSize.width / 2,
            y: point.y - contentSize.height / 2
        )
        let result = CGPoint(
            x: centered.x * cosine - centered.y * sine + rotatedSize.width / 2,
            y: centered.x * sine + centered.y * cosine + rotatedSize.height / 2
        )
        return result.isFinite ? result : .zero
    }

    /// Converts a point in a rotated bounding box back into the original logical coordinates.
    public static func contentPoint(
        fromRotated point: CGPoint,
        contentSize: CGSize,
        rotationDegrees: Double
    ) -> CGPoint {
        let rotatedSize = rotatedContentSize(contentSize, rotationDegrees: rotationDegrees)
        guard point.isFinite, contentSize.isValidViewportSize, rotatedSize.isValidViewportSize else {
            return .zero
        }

        let (sine, cosine) = sineCosine(rotationDegrees: rotationDegrees)
        let centered = CGPoint(
            x: point.x - rotatedSize.width / 2,
            y: point.y - rotatedSize.height / 2
        )
        let result = CGPoint(
            x: centered.x * cosine + centered.y * sine + contentSize.width / 2,
            y: -centered.x * sine + centered.y * cosine + contentSize.height / 2
        )
        return result.isFinite ? result : .zero
    }

    /// Scale applied before rotation so the rotated content covers the full container.
    public static func fillScale(
        contentSize: CGSize,
        containerSize: CGSize,
        rotationDegrees: Double
    ) -> CGFloat {
        guard contentSize.isValidViewportSize, containerSize.isValidViewportSize else {
            return 1
        }

        let radians = normalize(rotationDegrees: rotationDegrees) * .pi / 180
        let cosine = CGFloat(abs(cos(radians)))
        let sine = CGFloat(abs(sin(radians)))
        let horizontalScale = (
            containerSize.width * cosine + containerSize.height * sine
        ) / contentSize.width
        let verticalScale = (
            containerSize.width * sine + containerSize.height * cosine
        ) / contentSize.height
        let scale = max(horizontalScale, verticalScale)
        return scale.isFinite && scale > 0 ? scale : 1
    }
}

private extension ViewportGeometry {
    static let doubleTapScaleMultiplier: CGFloat = 4

    func centeredOffset(at scale: CGFloat) -> CGPoint {
        let transformedSize = contentSize(at: scale)
        guard transformedSize.isValidViewportSize, containerSize.isValidViewportSize else {
            return .zero
        }

        let result = CGPoint(
            x: (containerSize.width - transformedSize.width) / 2,
            y: (containerSize.height - transformedSize.height) / 2
        )
        return result.isFinite ? result : .zero
    }

    func clampedAxisOffset(
        _ offset: CGFloat,
        contentLength: CGFloat,
        containerLength: CGFloat
    ) -> CGFloat {
        guard offset.isFinite, contentLength.isFinite, containerLength.isFinite else {
            return 0
        }

        switch configuration.panPolicy {
        case .contained:
            if contentLength <= containerLength {
                return (containerLength - contentLength) / 2
            }
            return min(max(offset, containerLength - contentLength), 0)

        case .minimumVisible(let requestedLength):
            let visibleLength = min(max(requestedLength, 0), contentLength, containerLength)
            let minimumOffset = visibleLength - contentLength
            let maximumOffset = containerLength - visibleLength
            return min(max(offset, minimumOffset), maximumOffset)
        }
    }

    func safeAnchor(_ anchor: CGPoint) -> CGPoint {
        guard anchor.isFinite, containerSize.isValidViewportSize else {
            return containerCenter
        }

        return CGPoint(
            x: min(max(anchor.x, 0), containerSize.width),
            y: min(max(anchor.y, 0), containerSize.height)
        )
    }

    func clampedToVisibleContent(_ point: CGPoint, transform: ViewportTransform) -> CGPoint {
        let transformedSize = contentSize(at: transform.scale)
        guard transformedSize.isValidViewportSize, containerSize.isValidViewportSize else {
            return safeAnchor(point)
        }

        let contentRectangle = CGRect(origin: transform.offset, size: transformedSize)
        let containerRectangle = CGRect(origin: .zero, size: containerSize)
        let visibleRectangle = contentRectangle.intersection(containerRectangle)
        guard !visibleRectangle.isNull, !visibleRectangle.isEmpty else {
            return safeAnchor(point)
        }

        let point = point.isFinite
            ? point
            : CGPoint(x: visibleRectangle.midX, y: visibleRectangle.midY)
        return CGPoint(
            x: min(max(point.x, visibleRectangle.minX), visibleRectangle.maxX),
            y: min(max(point.y, visibleRectangle.minY), visibleRectangle.maxY)
        )
    }

    func safelyMultiplied(_ value: CGFloat, by multiplier: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0, multiplier.isFinite, multiplier > 0 else {
            return fitScale
        }
        guard value <= .greatestFiniteMagnitude / multiplier else {
            return .greatestFiniteMagnitude
        }
        return value * multiplier
    }
}

// Internal, not private: ViewportModel.swift uses these helpers too. See CODE_AUDIT_19 §9.23.
extension ViewportPanPolicy {
    var validViewportPolicy: ViewportPanPolicy {
        switch self {
        case .contained:
            return .contained
        case .minimumVisible(let length):
            return .minimumVisible(length.isFinite && length > 0 ? length : 0)
        }
    }
}

extension CGFloat {
    var validScaleMultiplier: CGFloat {
        isFinite && self >= 1 ? self : 8
    }
}

extension CGSize {
    var isValidViewportSize: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }

    var validViewportSize: CGSize {
        isValidViewportSize ? self : .zero
    }

    var isFinite: Bool {
        width.isFinite && height.isFinite
    }
}

extension CGPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}
