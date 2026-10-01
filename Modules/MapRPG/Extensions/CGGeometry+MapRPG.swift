// @copyright André Trettin

import CoreGraphics
import CoreRPG

/// Shared geometry validity checks and bounding-box math. Previously
/// reimplemented independently across `MapEditorSession`,
/// `MapCanvasGeometryResolver`, `MapOverlayGeometry`, `MapEntryModel`,
/// `DisplayConfigEditor`, and `MapRoomCanvas` — see CODE_AUDIT §9.5/§9.6.
extension CGSize {
    /// Forwards to CoreRPG's single definition. See CODE_AUDIT_20 §9.9.
    var isFiniteAndPositive: Bool {
        isValidViewportSize
    }
}

extension CGRect {
    var isFiniteAndPositive: Bool {
        origin.x.isFinite && origin.y.isFinite && size.isFiniteAndPositive
    }
}

extension Array where Element == CGPoint {
    /// The smallest rect containing every point, computed in one pass.
    /// `nil` for an empty array.
    var bounds: CGRect? {
        guard let first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
