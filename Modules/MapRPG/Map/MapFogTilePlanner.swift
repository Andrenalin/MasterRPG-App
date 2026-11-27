// @copyright André Trettin

import CoreRPG
import SwiftUI

// The fog tile geometry, split out of MapRoomCanvas.swift. See CODE_AUDIT_29 §9.9.

struct MapRoomSnapshot {
    let path: Path
    let bounds: CGRect
    let isShown: Bool
}

/// A fog coverage plan deliberately preserves one path per hidden room.
/// Combining these paths changes overlap semantics when polygon winding differs.
struct MapFogCoveragePlan {
    let snapshots: [MapRoomSnapshot]

    func coverageDepth(at point: CGPoint) -> Int {
        snapshots.count { $0.path.contains(point) }
    }
}

struct MapFogTileDrawPlan {
    let snapshot: MapRoomSnapshot
    let columns: [CGFloat]
    let rows: [CGFloat]

    var tileCount: Int { columns.count * rows.count }
}

/// The 2D map's per-room tile budget, shared with the 3D board so both show solid fog for the
/// same rooms. See CODE_AUDIT_19 §5.18.
public enum MapFogTileBudget {
    /// Whether a room with `roomBounds` is filled with the repeated `tileRectangle` (both in
    /// canvas coordinates) rather than solid fog.
    public static func allowsTiling(roomBounds: CGRect, tileRectangle: CGRect) -> Bool {
        MapFogTilePlanner(tileRectangle: tileRectangle).tileOrigins(covering: roomBounds) != nil
    }
}

/// Plans repeated fog tiles independently for each room. The former global
/// limit made a group of otherwise inexpensive rooms lose its tile whenever
/// their aggregate count crossed the threshold.
struct MapFogTilePlanner {
    /// The default tile budget of a room, and the cap of tile origins along one axis.
    /// See CODE_AUDIT_29 §9.10.
    static let maximumTilesPerAxis = 4_096

    init(tileRectangle: CGRect, maximumTilesPerRoom: Int = Self.maximumTilesPerAxis) {
        self.tileRectangle = tileRectangle
        self.maximumTilesPerRoom = maximumTilesPerRoom
    }

    let tileRectangle: CGRect
    let maximumTilesPerRoom: Int

    /// - Parameter visibleRect: when given, only the tiles that reach into it are drawn. The
    ///   budget is still decided on the whole room, so a room is tiled or solid whatever is
    ///   visible, and the 2D and 3D maps agree. See CODE_AUDIT_26 §7.53.
    func drawPlan(for snapshot: MapRoomSnapshot, visibleRect: CGRect? = nil) -> MapFogTileDrawPlan? {
        guard let origins = tileOrigins(covering: snapshot.bounds) else { return nil }
        guard let visibleRect, !visibleRect.isInfinite else {
            return MapFogTileDrawPlan(snapshot: snapshot, columns: origins.columns, rows: origins.rows)
        }
        let columns = origins.columns.filter { $0 + tileRectangle.width >= visibleRect.minX && $0 <= visibleRect.maxX }
        let rows = origins.rows.filter { $0 + tileRectangle.height >= visibleRect.minY && $0 <= visibleRect.maxY }
        return MapFogTileDrawPlan(snapshot: snapshot, columns: columns, rows: rows)
    }

    /// The tile lattice's column and row origins covering `bounds`, or `nil` (solid fog) when
    /// the room needs more than `maximumTilesPerRoom` tiles.
    func tileOrigins(covering bounds: CGRect) -> (columns: [CGFloat], rows: [CGFloat])? {
        guard maximumTilesPerRoom > 0 else { return nil }
        let maximumOriginsPerAxis = min(maximumTilesPerRoom, Self.maximumTilesPerAxis)
        let columns = tileOrigins(
            minimum: bounds.minX,
            maximum: bounds.maxX,
            sourceMinimum: tileRectangle.minX,
            length: tileRectangle.width,
            maximumCount: maximumOriginsPerAxis
        )
        let rows = tileOrigins(
            minimum: bounds.minY,
            maximum: bounds.maxY,
            sourceMinimum: tileRectangle.minY,
            length: tileRectangle.height,
            maximumCount: maximumOriginsPerAxis
        )
        guard !columns.isEmpty, !rows.isEmpty else { return nil }

        let (tileCount, didOverflow) = columns.count.multipliedReportingOverflow(by: rows.count)
        guard !didOverflow, tileCount <= maximumTilesPerRoom else { return nil }
        return (columns, rows)
    }

    private func tileOrigins(
        minimum: CGFloat,
        maximum: CGFloat,
        sourceMinimum: CGFloat,
        length: CGFloat,
        maximumCount: Int
    ) -> [CGFloat] {
        guard minimum.isFinite,
              maximum.isFinite,
              maximum >= minimum,
              sourceMinimum.isFinite,
              length.isFinite,
              length > 0,
              maximumCount > 0 else { return [] }

        let first = floor((minimum - sourceMinimum) / length) * length + sourceMinimum
        let rawCount = ceil((maximum - first) / length) + 1
        guard rawCount.isFinite,
              rawCount > 0,
              rawCount <= CGFloat(maximumCount) else { return [] }

        let count = max(1, Int(rawCount))
        return (0..<count).map { first + CGFloat($0) * length }
    }
}
