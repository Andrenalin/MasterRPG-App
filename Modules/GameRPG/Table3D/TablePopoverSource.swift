// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreGraphics
import Foundation
import simd

/// Where a popover points on the camera-based table: the frame of what it belongs to (a pin,
/// or the anchor of the map photo) in the table view's coordinate space. Pure, so it is
/// unit-tested without RealityKit.
struct TablePopoverSource: Equatable {
    /// What the popover belongs to: a pin's id, or the shown photo's item id.
    let id: UUID
    let frame: CGRect

    /// The eight corners of a box.
    static func corners(min: SIMD3<Float>, max: SIMD3<Float>) -> [SIMD3<Float>] {
        [min.x, max.x].flatMap { x in
            [min.y, max.y].flatMap { y in
                [min.z, max.z].map { z in SIMD3<Float>(x, y, z) }
            }
        }
    }

    /// The rectangle enclosing a pin's projected corners. `nil` when a corner has no projection
    /// (the pin is behind the camera) or the projection isn't finite.
    static func frame(enclosing points: [CGPoint?]) -> CGRect? {
        let projected = points.compactMap(\.self)
        guard !projected.isEmpty, projected.count == points.count,
              projected.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let horizontal = projected.map(\.x)
        let vertical = projected.map(\.y)
        guard let minX = horizontal.min(), let maxX = horizontal.max(),
              let minY = vertical.min(), let maxY = vertical.max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether `other` is far enough from this source to be worth a view update. The source is
    /// recomputed every rendered frame; a resting camera must not invalidate the popover on
    /// sub-point projection noise.
    func differsVisibly(from other: TablePopoverSource?) -> Bool {
        guard let other, other.id == id else { return true }
        return abs(frame.minX - other.frame.minX) >= Self.visibleChange
            || abs(frame.minY - other.frame.minY) >= Self.visibleChange
            || abs(frame.maxX - other.frame.maxX) >= Self.visibleChange
            || abs(frame.maxY - other.frame.maxY) >= Self.visibleChange
    }

    private static let visibleChange: CGFloat = 0.5
}
#endif
