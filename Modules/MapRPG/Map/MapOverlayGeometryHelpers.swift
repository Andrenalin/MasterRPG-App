// @copyright André Trettin

import CoreGraphics

/// Shared `CGPoint`/`CGRect` helpers used by the map overlay geometry family
/// (`MapOverlayGeometry.swift`, `MapOverlayFanGeometry.swift`,
/// `MapOverlayLoupeGeometry.swift`) — hoisted out when that file was split.
/// See CODE_AUDIT §9.13.
extension CGPoint {
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

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
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
