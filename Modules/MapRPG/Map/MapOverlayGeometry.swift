// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

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

/// The viewport-space quadrant occupied by an adaptive map action menu.
enum MapOverlayQuadrant: CaseIterable, Equatable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    fileprivate var startAngle: CGFloat {
        switch self {
        case .topLeading: .pi
        case .topTrailing: -.pi / 2
        case .bottomLeading: .pi / 2
        case .bottomTrailing: 0
        }
    }

    fileprivate var horizontalDirection: CGFloat {
        switch self {
        case .topLeading, .bottomLeading: -1
        case .topTrailing, .bottomTrailing: 1
        }
    }

    fileprivate var verticalDirection: CGFloat {
        switch self {
        case .topLeading, .topTrailing: -1
        case .bottomLeading, .bottomTrailing: 1
        }
    }

    fileprivate var horizontallyFlipped: Self {
        switch self {
        case .topLeading: .topTrailing
        case .topTrailing: .topLeading
        case .bottomLeading: .bottomTrailing
        case .bottomTrailing: .bottomLeading
        }
    }

    fileprivate var verticallyFlipped: Self {
        switch self {
        case .topLeading: .bottomLeading
        case .topTrailing: .bottomTrailing
        case .bottomLeading: .topLeading
        case .bottomTrailing: .topTrailing
        }
    }
}

/// The preferred vertical side for a fan centered on the source anchor.
/// Vertical fans keep every action above or below its map item and flip to the
/// opposite side when the preferred side would intersect viewport chrome.
enum MapOverlayVerticalDirection: Equatable, Sendable {
    case top
    case bottom

    fileprivate var centerAngle: CGFloat {
        switch self {
        case .top: -.pi / 2
        case .bottom: .pi / 2
        }
    }

    fileprivate var opposite: Self {
        switch self {
        case .top: .bottom
        case .bottom: .top
        }
    }

    fileprivate var representativeQuadrant: MapOverlayQuadrant {
        switch self {
        case .top: .topTrailing
        case .bottom: .bottomTrailing
        }
    }
}

/// A resolved fan layout. Centers are in viewport coordinates, so the menu can
/// stay outside the transformed map and retain a constant physical size.
struct MapAdaptiveFanPlacement: Sendable {
    let sourceAnchor: CGPoint
    let layoutAnchor: CGPoint
    let quadrant: MapOverlayQuadrant
    let buttonSize: CGSize
    let minimumCenterSpacing: CGFloat
    let centers: [CGPoint]
    let isValid: Bool
    let isFullyVisible: Bool

    var buttonFrames: [CGRect] {
        centers.map { center in
            CGRect(
                x: center.x - buttonSize.width / 2,
                y: center.y - buttonSize.height / 2,
                width: buttonSize.width,
                height: buttonSize.height
            )
        }
    }

    var offsets: [CGSize] {
        centers.map { center in
            CGSize(
                width: center.x - sourceAnchor.x,
                height: center.y - sourceAnchor.y
            )
        }
    }

    func center(at index: Int) -> CGPoint? {
        guard centers.indices.contains(index) else { return nil }
        return centers[index]
    }

    func offset(at index: Int) -> CGSize? {
        guard offsets.indices.contains(index) else { return nil }
        return offsets[index]
    }
}

/// Pure layout math for viewport-space map action menus.
enum MapAdaptiveFanGeometry {
    static let buttonSize = CGSize(width: 48, height: 48)
    static let minimumCenterSpacing: CGFloat = 60
    static let edgeInset: CGFloat = 12

    private static let minimumRadius: CGFloat = 96

    static func placement(
        anchor: CGPoint,
        itemCount: Int,
        viewport: CGRect,
        preferredQuadrant: MapOverlayQuadrant = .topTrailing
    ) -> MapAdaptiveFanPlacement {
        guard itemCount > 0,
              viewport.isFiniteAndPositive,
              viewport.width >= buttonSize.width + edgeInset * 2,
              viewport.height >= buttonSize.height + edgeInset * 2,
              anchor.isFinite else {
            return invalidPlacement(
                anchor: anchor.isFinite ? anchor : .zero,
                preferredQuadrant: preferredQuadrant
            )
        }

        let safeButtonCenterRect = viewport.insetBy(
            dx: buttonSize.width / 2 + edgeInset,
            dy: buttonSize.height / 2 + edgeInset
        )
        guard !safeButtonCenterRect.isNull,
              safeButtonCenterRect.origin.x.isFinite,
              safeButtonCenterRect.origin.y.isFinite,
              safeButtonCenterRect.width >= 0,
              safeButtonCenterRect.height >= 0 else {
            return invalidPlacement(
                anchor: anchor,
                preferredQuadrant: preferredQuadrant
            )
        }

        let layoutAnchor = anchor.clamped(to: safeButtonCenterRect)
        let radius = fanRadius(itemCount: itemCount)
        let preferenceOrder = quadrantPreferenceOrder(startingAt: preferredQuadrant)
        let safeFrame = viewport.insetBy(dx: edgeInset, dy: edgeInset)

        let candidates = preferenceOrder.enumerated().map { rank, quadrant in
            let centers = rawCenters(
                anchor: layoutAnchor,
                itemCount: itemCount,
                radius: radius,
                quadrant: quadrant
            )
            let framesBounds = framesBounds(for: centers)
            let overflow = framesBounds.overflowDistance(from: safeFrame)
            let capacity = directionalCapacity(
                from: layoutAnchor,
                in: safeButtonCenterRect,
                quadrant: quadrant,
                radius: radius
            )
            return FanCandidate(
                quadrant: quadrant,
                centers: centers,
                overflow: overflow,
                capacity: capacity,
                preferenceRank: rank
            )
        }

        guard let candidate = candidates.min(by: candidatePrecedes) else {
            return invalidPlacement(
                anchor: anchor,
                preferredQuadrant: preferredQuadrant
            )
        }

        let translation = groupTranslation(
            centers: candidate.centers,
            into: safeButtonCenterRect
        )
        let centers = candidate.centers.map { center in
            CGPoint(
                x: center.x + translation.width,
                y: center.y + translation.height
            )
        }
        let isFullyVisible = centers.allSatisfy(safeButtonCenterRect.contains)

        return MapAdaptiveFanPlacement(
            sourceAnchor: anchor,
            layoutAnchor: layoutAnchor,
            quadrant: candidate.quadrant,
            buttonSize: buttonSize,
            minimumCenterSpacing: minimumCenterSpacing,
            centers: centers,
            isValid: true,
            isFullyVisible: isFullyVisible
        )
    }

    /// Places a compact fan centered vertically above or below its anchor.
    /// When a small item count does not need the full 90-degree arc, the arc
    /// narrows to the requested center spacing instead of spreading across the
    /// minimum radius.
    static func verticalPlacement(
        anchor: CGPoint,
        itemCount: Int,
        viewport: CGRect,
        preferredDirection: MapOverlayVerticalDirection,
        centerSpacing: CGFloat = minimumCenterSpacing
    ) -> MapAdaptiveFanPlacement {
        let resolvedCenterSpacing = max(
            minimumCenterSpacing,
            centerSpacing.isFinite ? centerSpacing : minimumCenterSpacing
        )
        guard itemCount > 0,
              viewport.isFiniteAndPositive,
              viewport.width >= buttonSize.width + edgeInset * 2,
              viewport.height >= buttonSize.height + edgeInset * 2,
              anchor.isFinite else {
            return invalidPlacement(
                anchor: anchor.isFinite ? anchor : .zero,
                preferredQuadrant: preferredDirection.representativeQuadrant
            )
        }

        let safeButtonCenterRect = viewport.insetBy(
            dx: buttonSize.width / 2 + edgeInset,
            dy: buttonSize.height / 2 + edgeInset
        )
        guard !safeButtonCenterRect.isNull,
              safeButtonCenterRect.origin.x.isFinite,
              safeButtonCenterRect.origin.y.isFinite,
              safeButtonCenterRect.width >= 0,
              safeButtonCenterRect.height >= 0 else {
            return invalidPlacement(
                anchor: anchor,
                preferredQuadrant: preferredDirection.representativeQuadrant
            )
        }

        let layoutAnchor = anchor.clamped(to: safeButtonCenterRect)
        let radius = fanRadius(itemCount: itemCount)
        let safeFrame = viewport.insetBy(dx: edgeInset, dy: edgeInset)
        let directions = [preferredDirection, preferredDirection.opposite]
        let candidates = directions.enumerated().map { rank, direction in
            let centers = verticallyCenteredCenters(
                anchor: layoutAnchor,
                itemCount: itemCount,
                radius: radius,
                direction: direction,
                centerSpacing: resolvedCenterSpacing
            )
            return FanCandidate(
                quadrant: direction.representativeQuadrant,
                centers: centers,
                overflow: framesBounds(for: centers).overflowDistance(from: safeFrame),
                capacity: verticalCapacity(
                    from: layoutAnchor,
                    in: safeButtonCenterRect,
                    direction: direction,
                    radius: radius
                ),
                preferenceRank: rank
            )
        }

        guard let candidate = candidates.min(by: candidatePrecedes) else {
            return invalidPlacement(
                anchor: anchor,
                preferredQuadrant: preferredDirection.representativeQuadrant
            )
        }

        let translation = groupTranslation(
            centers: candidate.centers,
            into: safeButtonCenterRect
        )
        let centers = candidate.centers.map { center in
            CGPoint(
                x: center.x + translation.width,
                y: center.y + translation.height
            )
        }

        return MapAdaptiveFanPlacement(
            sourceAnchor: anchor,
            layoutAnchor: layoutAnchor,
            quadrant: candidate.quadrant,
            buttonSize: buttonSize,
            minimumCenterSpacing: resolvedCenterSpacing,
            centers: centers,
            isValid: true,
            isFullyVisible: centers.allSatisfy(safeButtonCenterRect.contains)
        )
    }

    private static func invalidPlacement(
        anchor: CGPoint,
        preferredQuadrant: MapOverlayQuadrant
    ) -> MapAdaptiveFanPlacement {
        MapAdaptiveFanPlacement(
            sourceAnchor: anchor,
            layoutAnchor: anchor,
            quadrant: preferredQuadrant,
            buttonSize: buttonSize,
            minimumCenterSpacing: minimumCenterSpacing,
            centers: [],
            isValid: false,
            isFullyVisible: false
        )
    }

    private static func fanRadius(itemCount: Int) -> CGFloat {
        guard itemCount > 1 else { return minimumRadius }
        let step = (.pi / 2) / CGFloat(itemCount - 1)
        let chordFactor = 2 * sin(step / 2)
        guard chordFactor.isFinite, chordFactor > 0 else { return minimumRadius }
        return max(minimumRadius, minimumCenterSpacing / chordFactor)
    }

    private static func rawCenters(
        anchor: CGPoint,
        itemCount: Int,
        radius: CGFloat,
        quadrant: MapOverlayQuadrant
    ) -> [CGPoint] {
        let angles: [CGFloat]
        if itemCount == 1 {
            angles = [quadrant.startAngle + .pi / 4]
        } else {
            let step = (.pi / 2) / CGFloat(itemCount - 1)
            angles = (0..<itemCount).map { index in
                quadrant.startAngle + CGFloat(index) * step
            }
        }

        return angles.map { angle in
            CGPoint(
                x: anchor.x + cos(angle) * radius,
                y: anchor.y + sin(angle) * radius
            )
        }
    }

    private static func verticallyCenteredCenters(
        anchor: CGPoint,
        itemCount: Int,
        radius: CGFloat,
        direction: MapOverlayVerticalDirection,
        centerSpacing: CGFloat
    ) -> [CGPoint] {
        let angularStep: CGFloat
        if itemCount > 1 {
            let ratio = min(1, centerSpacing / (2 * radius))
            angularStep = 2 * asin(ratio)
        } else {
            angularStep = 0
        }
        let totalSpan = angularStep * CGFloat(max(0, itemCount - 1))
        let startAngle = direction.centerAngle - totalSpan / 2

        return (0..<itemCount).map { index in
            let angle = startAngle + CGFloat(index) * angularStep
            return CGPoint(
                x: anchor.x + cos(angle) * radius,
                y: anchor.y + sin(angle) * radius
            )
        }
    }

    private static func framesBounds(for centers: [CGPoint]) -> CGRect {
        guard let first = centers.first else { return .null }
        var bounds = CGRect(
            x: first.x - buttonSize.width / 2,
            y: first.y - buttonSize.height / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )
        for center in centers.dropFirst() {
            bounds = bounds.union(
                CGRect(
                    x: center.x - buttonSize.width / 2,
                    y: center.y - buttonSize.height / 2,
                    width: buttonSize.width,
                    height: buttonSize.height
                )
            )
        }
        return bounds
    }

    private static func centersBounds(for centers: [CGPoint]) -> CGRect {
        guard let first = centers.first else { return .null }
        var minimumX = first.x
        var maximumX = first.x
        var minimumY = first.y
        var maximumY = first.y
        for center in centers.dropFirst() {
            minimumX = min(minimumX, center.x)
            maximumX = max(maximumX, center.x)
            minimumY = min(minimumY, center.y)
            maximumY = max(maximumY, center.y)
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    private static func directionalCapacity(
        from anchor: CGPoint,
        in rect: CGRect,
        quadrant: MapOverlayQuadrant,
        radius: CGFloat
    ) -> CGFloat {
        let horizontal = quadrant.horizontalDirection < 0
            ? anchor.x - rect.minX
            : rect.maxX - anchor.x
        let vertical = quadrant.verticalDirection < 0
            ? anchor.y - rect.minY
            : rect.maxY - anchor.y
        return min(max(0, horizontal), radius) + min(max(0, vertical), radius)
    }

    private static func verticalCapacity(
        from anchor: CGPoint,
        in rect: CGRect,
        direction: MapOverlayVerticalDirection,
        radius: CGFloat
    ) -> CGFloat {
        let available = direction == .top
            ? anchor.y - rect.minY
            : rect.maxY - anchor.y
        return min(max(0, available), radius)
    }

    private static func quadrantPreferenceOrder(
        startingAt preferred: MapOverlayQuadrant
    ) -> [MapOverlayQuadrant] {
        [
            preferred,
            preferred.horizontallyFlipped,
            preferred.verticallyFlipped,
            preferred.horizontallyFlipped.verticallyFlipped
        ]
    }

    private static func candidatePrecedes(
        _ lhs: FanCandidate,
        _ rhs: FanCandidate
    ) -> Bool {
        let tolerance: CGFloat = 0.001
        if abs(lhs.overflow - rhs.overflow) > tolerance {
            return lhs.overflow < rhs.overflow
        }
        if abs(lhs.capacity - rhs.capacity) > tolerance {
            return lhs.capacity > rhs.capacity
        }
        return lhs.preferenceRank < rhs.preferenceRank
    }

    private static func groupTranslation(
        centers: [CGPoint],
        into rect: CGRect
    ) -> CGSize {
        let bounds = centersBounds(for: centers)
        guard !bounds.isNull else { return .zero }

        let horizontal = axisTranslation(
            minimum: bounds.minX,
            maximum: bounds.maxX,
            targetMinimum: rect.minX,
            targetMaximum: rect.maxX
        )
        let vertical = axisTranslation(
            minimum: bounds.minY,
            maximum: bounds.maxY,
            targetMinimum: rect.minY,
            targetMaximum: rect.maxY
        )
        return CGSize(width: horizontal, height: vertical)
    }

    private static func axisTranslation(
        minimum: CGFloat,
        maximum: CGFloat,
        targetMinimum: CGFloat,
        targetMaximum: CGFloat
    ) -> CGFloat {
        let length = maximum - minimum
        let targetLength = targetMaximum - targetMinimum
        guard length <= targetLength else {
            return (targetMinimum + targetMaximum) / 2 - (minimum + maximum) / 2
        }
        if minimum < targetMinimum { return targetMinimum - minimum }
        if maximum > targetMaximum { return targetMaximum - maximum }
        return 0
    }
}

private struct FanCandidate: Sendable {
    let quadrant: MapOverlayQuadrant
    let centers: [CGPoint]
    let overflow: CGFloat
    let capacity: CGFloat
    let preferenceRank: Int
}

enum MapLoupeInteractionKind: Equatable, Sendable {
    case touch
    case pointerOrSpatial
}

enum MapLoupeCorner: Equatable, Sendable {
    case upperLeading
    case upperTrailing
    case lowerLeading
    case lowerTrailing

    fileprivate var horizontalDirection: CGFloat {
        switch self {
        case .upperLeading, .lowerLeading: -1
        case .upperTrailing, .lowerTrailing: 1
        }
    }

    fileprivate var verticalDirection: CGFloat {
        switch self {
        case .upperLeading, .upperTrailing: -1
        case .lowerLeading, .lowerTrailing: 1
        }
    }
}

struct MapLoupePlacement: Sendable {
    let center: CGPoint
    let frame: CGRect
    let corner: MapLoupeCorner?
    let isValid: Bool
    let isFullyVisible: Bool
    let wasClamped: Bool
}

struct MapLoupeSampling: Equatable, Sendable {
    let scale: CGFloat
    let offset: CGPoint

    /// Destination for a logical map canvas inside the fixed loupe. The
    /// sampled content coordinate maps exactly to the loupe center.
    func destinationRectangle(canvasSize: CGSize) -> CGRect {
        guard canvasSize.width.isFinite,
              canvasSize.height.isFinite,
              canvasSize.width > 0,
              canvasSize.height > 0,
              scale.isFinite,
              scale > 0,
              offset.isFinite else { return .zero }
        return CGRect(
            origin: offset,
            size: CGSize(
                width: canvasSize.width * scale,
                height: canvasSize.height * scale
            )
        )
    }
}

/// Pure placement math for the fixed-size map needle loupe. Sampling geometry
/// remains independent: views position with the needle head and sample the
/// persisted needle-tip coordinate.
enum MapLoupeGeometry {
    static let size = CGSize(width: 160, height: 160)
    static let gap: CGFloat = 24
    static let edgeInset: CGFloat = 12

    static func sampling(
        sampleCoordinate: CGPoint,
        viewportScale: CGFloat,
        magnification: CGFloat = 3
    ) -> MapLoupeSampling {
        let safeViewportScale = viewportScale.isFinite && viewportScale > 0
            ? viewportScale
            : 1
        let safeMagnification = magnification.isFinite && magnification > 0
            ? magnification
            : 3
        let scale = safeViewportScale * safeMagnification
        let coordinate = sampleCoordinate.isFinite ? sampleCoordinate : .zero
        return MapLoupeSampling(
            scale: scale,
            offset: CGPoint(
                x: size.width / 2 - coordinate.x * scale,
                y: size.height / 2 - coordinate.y * scale
            )
        )
    }

    static func placement(
        needleHead: CGPoint,
        viewport: CGRect,
        interaction: MapLoupeInteractionKind
    ) -> MapLoupePlacement {
        guard viewport.isFiniteAndPositive,
              viewport.width > edgeInset * 2,
              viewport.height > edgeInset * 2,
              needleHead.isFinite else {
            return MapLoupePlacement(
                center: .zero,
                frame: .zero,
                corner: nil,
                isValid: false,
                isFullyVisible: false,
                wasClamped: false
            )
        }

        let safeFrame = viewport.insetBy(dx: edgeInset, dy: edgeInset)
        let corners = preferredCorners(for: interaction)
        let candidates = corners.enumerated().map { rank, corner in
            let center = candidateCenter(needleHead: needleHead, corner: corner)
            let candidateFrame = loupeFrame(centeredAt: center)
            return LoupeCandidate(
                center: center,
                frame: candidateFrame,
                corner: corner,
                overflow: candidateFrame.overflowDistance(from: safeFrame),
                preferenceRank: rank
            )
        }

        let candidate = candidates.first(where: { safeFrame.contains($0.frame) })
            ?? candidates.min { lhs, rhs in
                let tolerance: CGFloat = 0.001
                if abs(lhs.overflow - rhs.overflow) > tolerance {
                    return lhs.overflow < rhs.overflow
                }
                return lhs.preferenceRank < rhs.preferenceRank
            }

        guard let candidate else {
            return MapLoupePlacement(
                center: viewport.center,
                frame: loupeFrame(centeredAt: viewport.center),
                corner: nil,
                isValid: false,
                isFullyVisible: false,
                wasClamped: false
            )
        }

        let center = clampedCenter(candidate.center, inside: safeFrame)
        let resolvedFrame = loupeFrame(centeredAt: center)
        return MapLoupePlacement(
            center: center,
            frame: resolvedFrame,
            corner: candidate.corner,
            isValid: true,
            isFullyVisible: safeFrame.contains(resolvedFrame),
            wasClamped: center != candidate.center
        )
    }

    private static func preferredCorners(
        for interaction: MapLoupeInteractionKind
    ) -> [MapLoupeCorner] {
        switch interaction {
        case .touch:
            [.upperLeading, .lowerTrailing]
        case .pointerOrSpatial:
            [.upperTrailing, .upperLeading, .lowerTrailing, .lowerLeading]
        }
    }

    private static func candidateCenter(
        needleHead: CGPoint,
        corner: MapLoupeCorner
    ) -> CGPoint {
        let horizontalDistance = size.width / 2 + gap
        let verticalDistance = size.height / 2 + gap
        return CGPoint(
            x: needleHead.x + corner.horizontalDirection * horizontalDistance,
            y: needleHead.y + corner.verticalDirection * verticalDistance
        )
    }

    private static func loupeFrame(centeredAt center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func clampedCenter(
        _ center: CGPoint,
        inside safeFrame: CGRect
    ) -> CGPoint {
        let minimumX = safeFrame.minX + size.width / 2
        let maximumX = safeFrame.maxX - size.width / 2
        let minimumY = safeFrame.minY + size.height / 2
        let maximumY = safeFrame.maxY - size.height / 2

        guard minimumX <= maximumX, minimumY <= maximumY else {
            return safeFrame.center
        }
        return CGPoint(
            x: min(max(center.x, minimumX), maximumX),
            y: min(max(center.y, minimumY), maximumY)
        )
    }
}

private struct LoupeCandidate: Sendable {
    let center: CGPoint
    let frame: CGRect
    let corner: MapLoupeCorner
    let overflow: CGFloat
    let preferenceRank: Int
}

private extension CGPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }

    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var isFiniteAndPositive: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }

    func overflowDistance(from containingRect: CGRect) -> CGFloat {
        guard !isNull else { return .infinity }
        let leading = max(0, containingRect.minX - minX)
        let trailing = max(0, maxX - containingRect.maxX)
        let top = max(0, containingRect.minY - minY)
        let bottom = max(0, maxY - containingRect.maxY)
        return leading * leading
            + trailing * trailing
            + top * top
            + bottom * bottom
    }
}
