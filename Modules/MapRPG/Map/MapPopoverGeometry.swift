// @copyright André Trettin

import CoreGraphics
import Foundation

/// The side of the source item on which a map popover appears.
enum MapPopoverSide: CaseIterable, Equatable, Sendable {
    case trailing
    case leading
    case bottom
    case top

    /// Whether the arrow sits on a vertical (leading/trailing) panel edge.
    var isHorizontal: Bool {
        self == .trailing || self == .leading
    }
}

/// A resolved popover layout in viewport coordinates. `frame` includes the
/// arrow, which points from the panel edge facing the source toward the
/// source's center.
struct MapPopoverPlacement: Equatable, Sendable {
    let frame: CGRect
    let side: MapPopoverSide
    /// Arrow tip position along the panel edge facing the source, measured
    /// from that edge's minimum (top for a side popover, leading otherwise).
    let arrowOffset: CGFloat
    let isValid: Bool
    let isFullyVisible: Bool
}

/// Pure layout math for the non-modal pin popover. The popover lives in
/// viewport space, so it follows its pin while the canvas pans or zooms.
enum MapPopoverGeometry {
    static let arrowLength: CGFloat = 12
    static let arrowWidth: CGFloat = 26
    static let cornerRadius: CGFloat = 28
    static let edgeInset: CGFloat = 8

    /// Places a panel of `contentSize` (arrow excluded) next to `source`,
    /// trying `preferredSides` in order and falling back to the side with the
    /// most room when none fits completely.
    static func placement(
        source: CGRect,
        contentSize: CGSize,
        viewport: CGRect,
        preferredSides: [MapPopoverSide] = MapPopoverSide.allCases
    ) -> MapPopoverPlacement {
        guard source.isFiniteRect,
              viewport.isFiniteRect,
              contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0,
              viewport.width > edgeInset * 2, viewport.height > edgeInset * 2 else {
            return MapPopoverPlacement(
                frame: .zero,
                side: preferredSides.first ?? .trailing,
                arrowOffset: 0,
                isValid: false,
                isFullyVisible: false
            )
        }

        let safeFrame = viewport.insetBy(dx: edgeInset, dy: edgeInset)
        let sides = preferredSides.isEmpty ? MapPopoverSide.allCases : preferredSides
        let side = sides.first { availableRoom(on: $0, of: source, in: safeFrame) >= requiredRoom(on: $0, for: contentSize) }
            ?? sides.max { firstSide, secondSide in
                roomRatio(on: firstSide, source: source, safeFrame: safeFrame, contentSize: contentSize)
                    < roomRatio(on: secondSide, source: source, safeFrame: safeFrame, contentSize: contentSize)
            }
            ?? .trailing

        let size = frameSize(for: contentSize, side: side)
        var origin: CGPoint = switch side {
        case .trailing:
            CGPoint(x: source.maxX, y: source.midY - size.height / 2)
        case .leading:
            CGPoint(x: source.minX - size.width, y: source.midY - size.height / 2)
        case .bottom:
            CGPoint(x: source.midX - size.width / 2, y: source.maxY)
        case .top:
            CGPoint(x: source.midX - size.width / 2, y: source.minY - size.height)
        }
        origin.x = clamp(origin.x, lower: safeFrame.minX, upper: safeFrame.maxX - size.width)
        origin.y = clamp(origin.y, lower: safeFrame.minY, upper: safeFrame.maxY - size.height)
        let frame = CGRect(origin: origin, size: size)

        let edgeLength = side.isHorizontal ? size.height : size.width
        let sourceCenter = side.isHorizontal ? source.midY - frame.minY : source.midX - frame.minX
        let arrowInset = cornerRadius + arrowWidth / 2
        let arrowOffset = clamp(sourceCenter, lower: arrowInset, upper: edgeLength - arrowInset)

        return MapPopoverPlacement(
            frame: frame,
            side: side,
            arrowOffset: arrowOffset,
            isValid: true,
            isFullyVisible: safeFrame.contains(frame)
        )
    }

    static func frameSize(for contentSize: CGSize, side: MapPopoverSide) -> CGSize {
        side.isHorizontal
            ? CGSize(width: contentSize.width + arrowLength, height: contentSize.height)
            : CGSize(width: contentSize.width, height: contentSize.height + arrowLength)
    }

    private static func requiredRoom(on side: MapPopoverSide, for contentSize: CGSize) -> CGFloat {
        let size = frameSize(for: contentSize, side: side)
        return side.isHorizontal ? size.width : size.height
    }

    private static func availableRoom(on side: MapPopoverSide, of source: CGRect, in safeFrame: CGRect) -> CGFloat {
        switch side {
        case .trailing: safeFrame.maxX - source.maxX
        case .leading: source.minX - safeFrame.minX
        case .bottom: safeFrame.maxY - source.maxY
        case .top: source.minY - safeFrame.minY
        }
    }

    private static func roomRatio(
        on side: MapPopoverSide,
        source: CGRect,
        safeFrame: CGRect,
        contentSize: CGSize
    ) -> CGFloat {
        availableRoom(on: side, of: source, in: safeFrame) / requiredRoom(on: side, for: contentSize)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

private extension CGRect {
    var isFiniteRect: Bool {
        !isNull && !isInfinite
            && origin.x.isFinite && origin.y.isFinite
            && width.isFinite && height.isFinite
    }
}
