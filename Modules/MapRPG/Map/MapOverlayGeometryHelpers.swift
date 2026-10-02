// @copyright André Trettin

import CoreGraphics

/// Shared `CGRect` helpers used by the map overlay geometry family
/// (`MapOverlayGeometry.swift`, `MapOverlayLoupeGeometry.swift`) — hoisted out
/// when that file was split. See CODE_AUDIT §9.13.
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
