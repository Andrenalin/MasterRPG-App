// @copyright André Trettin

import CoreGraphics
import Foundation

struct ImageViewportConfiguration: Equatable, Sendable {
    init(id: UUID, imageSize: CGSize, containerSize: CGSize, degrees: Double) {
        self.id = id
        self.imageSize = imageSize.validViewportSize
        self.containerSize = containerSize.validViewportSize
        self.degrees = ImageViewportGeometry.normalize(degrees)
    }

    let id: UUID
    let imageSize: CGSize
    let containerSize: CGSize
    let degrees: Double
}

struct ImageViewport: Equatable, Sendable {
    let scale: CGFloat
    let offset: CGPoint
}

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
        guard originalImageSize.isValidViewportSize else {
            return .zero
        }

        let radians = normalizedDegrees * .pi / 180
        let cosine = CGFloat(abs(cos(radians)))
        let sine = CGFloat(abs(sin(radians)))
        let width = originalImageSize.width * cosine + originalImageSize.height * sine
        let height = originalImageSize.width * sine + originalImageSize.height * cosine
        let size = CGSize(width: width, height: height)
        return size.isValidViewportSize ? size : .zero
    }

    var fitScale: CGFloat {
        guard configuration.containerSize.isValidViewportSize,
              rotatedImageSize.isValidViewportSize else {
            return 1
        }

        let widthScale = configuration.containerSize.width / rotatedImageSize.width
        let heightScale = configuration.containerSize.height / rotatedImageSize.height
        let scale = min(widthScale, heightScale)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    var maximumScale: CGFloat {
        let multipliedScale: CGFloat
        if fitScale <= .greatestFiniteMagnitude / Self.maximumScaleMultiplier {
            multipliedScale = fitScale * Self.maximumScaleMultiplier
        } else {
            multipliedScale = .greatestFiniteMagnitude
        }
        return max(multipliedScale, 1)
    }

    var fitViewport: ImageViewport {
        ImageViewport(scale: fitScale, offset: centeredOffset(at: fitScale))
    }

    /// The scale needed for every corner of the container to remain inside the
    /// rotated image, including for non-cardinal rotation angles.
    var fillScale: CGFloat {
        guard configuration.containerSize.isValidViewportSize,
              originalImageSize.isValidViewportSize else {
            return 1
        }

        let radians = normalizedDegrees * .pi / 180
        let cosine = CGFloat(abs(cos(radians)))
        let sine = CGFloat(abs(sin(radians)))
        let horizontalScale = (
            configuration.containerSize.width * cosine
            + configuration.containerSize.height * sine
        ) / originalImageSize.width
        let verticalScale = (
            configuration.containerSize.width * sine
            + configuration.containerSize.height * cosine
        ) / originalImageSize.height
        let scale = max(horizontalScale, verticalScale)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else {
            return fitScale
        }
        return min(max(scale, fitScale), maximumScale)
    }

    func clampedOffset(_ offset: CGPoint, at scale: CGFloat) -> CGPoint {
        let scale = clampedScale(scale)
        guard let contentSize = contentSize(at: scale), offset.isFinite else {
            return centeredOffset(at: scale)
        }

        return CGPoint(
            x: clampedAxisOffset(
                offset.x,
                contentLength: contentSize.width,
                containerLength: configuration.containerSize.width
            ),
            y: clampedAxisOffset(
                offset.y,
                contentLength: contentSize.height,
                containerLength: configuration.containerSize.height
            )
        )
    }

    func zoomedViewport(from viewport: ImageViewport, toScale proposedScale: CGFloat, anchor: CGPoint) -> ImageViewport {
        guard rotatedImageSize.isValidViewportSize,
              configuration.containerSize.isValidViewportSize else {
            return fitViewport
        }

        let oldScale = clampedScale(viewport.scale)
        let oldOffset = clampedOffset(viewport.offset, at: oldScale)
        let newScale = clampedScale(proposedScale)
        let anchor = safeAnchor(anchor)
        let imagePoint = CGPoint(
            x: (anchor.x - oldOffset.x) / oldScale,
            y: (anchor.y - oldOffset.y) / oldScale
        )
        let proposedOffset = CGPoint(
            x: anchor.x - imagePoint.x * newScale,
            y: anchor.y - imagePoint.y * newScale
        )
        let newOffset = clampedOffset(proposedOffset, at: newScale)
        return ImageViewport(scale: newScale, offset: newOffset)
    }

    func doubleTapViewport(from viewport: ImageViewport, at location: CGPoint) -> ImageViewport {
        let currentScale = clampedScale(viewport.scale)
        let currentOffset = clampedOffset(viewport.offset, at: currentScale)
        let currentViewport = ImageViewport(scale: currentScale, offset: currentOffset)

        guard !approximatelyEqual(currentScale, fitScale) else {
            let proposedScale = safelyMultiplied(fitScale, by: Self.doubleTapScaleMultiplier)
            let anchor = clampedToVisibleImage(location, viewport: currentViewport)
            return zoomedViewport(from: currentViewport, toScale: proposedScale, anchor: anchor)
        }

        return fitViewport
    }

    static func normalize(_ degrees: Double) -> Double {
        guard degrees.isFinite else {
            return 0
        }

        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        let normalized = remainder < 0 ? remainder + 360 : remainder
        return abs(normalized) < Double.ulpOfOne * 360 ? 0 : normalized
    }
}

private extension ImageViewportGeometry {
    static let maximumScaleMultiplier: CGFloat = 8
    static let doubleTapScaleMultiplier: CGFloat = 4
    static let comparisonTolerance: CGFloat = 0.0001

    func centeredOffset(at scale: CGFloat) -> CGPoint {
        guard let contentSize = contentSize(at: scale),
              configuration.containerSize.isValidViewportSize else {
            return .zero
        }

        let offset = CGPoint(
            x: (configuration.containerSize.width - contentSize.width) / 2,
            y: (configuration.containerSize.height - contentSize.height) / 2
        )
        return offset.isFinite ? offset : .zero
    }

    func contentSize(at scale: CGFloat) -> CGSize? {
        guard rotatedImageSize.isValidViewportSize, scale.isFinite, scale > 0 else {
            return nil
        }

        let contentSize = CGSize(
            width: rotatedImageSize.width * scale,
            height: rotatedImageSize.height * scale
        )
        return contentSize.isValidViewportSize ? contentSize : nil
    }

    func clampedAxisOffset(_ offset: CGFloat, contentLength: CGFloat, containerLength: CGFloat) -> CGFloat {
        guard offset.isFinite, contentLength.isFinite, containerLength.isFinite else {
            return 0
        }

        if contentLength <= containerLength {
            return (containerLength - contentLength) / 2
        }

        return min(max(offset, containerLength - contentLength), 0)
    }

    func safeAnchor(_ anchor: CGPoint) -> CGPoint {
        guard anchor.isFinite, configuration.containerSize.isValidViewportSize else {
            return CGPoint(
                x: configuration.containerSize.width / 2,
                y: configuration.containerSize.height / 2
            )
        }

        return CGPoint(
            x: min(max(anchor.x, 0), configuration.containerSize.width),
            y: min(max(anchor.y, 0), configuration.containerSize.height)
        )
    }

    func clampedToVisibleImage(_ point: CGPoint, viewport: ImageViewport) -> CGPoint {
        guard let contentSize = contentSize(at: viewport.scale),
              configuration.containerSize.isValidViewportSize else {
            return safeAnchor(point)
        }

        let imageRectangle = CGRect(origin: viewport.offset, size: contentSize)
        let containerRectangle = CGRect(origin: .zero, size: configuration.containerSize)
        let visibleRectangle = imageRectangle.intersection(containerRectangle)
        guard !visibleRectangle.isNull, !visibleRectangle.isEmpty else {
            return safeAnchor(point)
        }

        let point = point.isFinite ? point : CGPoint(x: visibleRectangle.midX, y: visibleRectangle.midY)
        return CGPoint(
            x: min(max(point.x, visibleRectangle.minX), visibleRectangle.maxX),
            y: min(max(point.y, visibleRectangle.minY), visibleRectangle.maxY)
        )
    }

    func safelyMultiplied(_ value: CGFloat, by multiplier: CGFloat) -> CGFloat {
        guard value <= .greatestFiniteMagnitude / multiplier else {
            return .greatestFiniteMagnitude
        }
        return value * multiplier
    }

    func approximatelyEqual(_ first: CGFloat, _ second: CGFloat) -> Bool {
        let tolerance = max(Self.comparisonTolerance, abs(second) * Self.comparisonTolerance)
        return abs(first - second) <= tolerance
    }
}

private extension CGSize {
    var isValidViewportSize: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }

    var validViewportSize: CGSize {
        isValidViewportSize ? self : .zero
    }
}

private extension CGPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}
