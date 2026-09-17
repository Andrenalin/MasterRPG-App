// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

// Split out of MapOverlayGeometry.swift — see CODE_AUDIT §9.13.

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
