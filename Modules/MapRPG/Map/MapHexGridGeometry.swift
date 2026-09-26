// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

/// Shared hex-grid sizing and layout math. Previously reimplemented
/// independently in `EditController` and `MapEditController` — see
/// CODE_AUDIT §9.2.
enum MapHexGridGeometry {
    /// Seed value for the default grid density: roughly this many hexes
    /// fit across the shorter map dimension when no size is requested yet.
    private static let defaultHexesAcrossShortSide: Double = 12

    @MainActor
    static func initialSize(for model: MapModel, requestedSize: Double) -> Double {
        let size: Double
        if requestedSize < 10 {
            let widthScale = model.width / (defaultHexesAcrossShortSide * sqrt(3))
            let heightScale = model.height / (defaultHexesAcrossShortSide * 1.5)
            size = max(widthScale, heightScale)
        } else {
            size = requestedSize
        }
        return fittedSize(size, width: model.width, height: model.height)
    }

    /// Hard cap on the number of hex cells generated in one call — protects against an
    /// unvalidated, very large map dimension with a small scale producing hundreds of
    /// thousands of `MapEntryModel`s. See CODE_AUDIT_17 §5.16.
    static let maxCells = 20_000

    /// Column and row count for a grid of `size` over `width × height`, or `nil` when the
    /// input is invalid or the counts don't fit in `Int` (checked conversions instead of a
    /// trapping `Int(_:)` of a huge quotient). See CODE_AUDIT_18 §5.6.
    static func dimensions(for size: Double, width: Double, height: Double) -> (columns: Int, rows: Int)? {
        guard size.isFinite, size > 0,
              width.isFinite, width > 0,
              height.isFinite, height > 0 else { return nil }
        let hexWidth = sqrt(3) * size
        guard let columns = Int(exactly: ((width + hexWidth / 2) / hexWidth).rounded(.down)),
              let rows = Int(exactly: ((height + size / 2) / (3 * size / 2)).rounded(.down)) else { return nil }
        let (safeColumns, columnsOverflow) = columns.addingReportingOverflow(1)
        let (safeRows, rowsOverflow) = rows.addingReportingOverflow(1)
        guard !columnsOverflow, !rowsOverflow, safeColumns > 0, safeRows > 0 else { return nil }
        return (safeColumns, safeRows)
    }

    static func cellCount(for size: Double, width: Double, height: Double) -> Int? {
        guard let dimensions = dimensions(for: size, width: width, height: height) else { return nil }
        let (count, overflow) = dimensions.columns.multipliedReportingOverflow(by: dimensions.rows)
        return overflow ? nil : count
    }

    /// The smallest hex size at or above `size` whose grid stays within `maxCells`. A size
    /// below that used to make `grid(for:in:)` return no cells, and `replaceGrid` then
    /// erased the existing grid (and its per-cell reveal state) without a message.
    /// See CODE_AUDIT_18 §5.6.
    static func fittedSize(_ size: Double, width: Double, height: Double) -> Double {
        guard size.isFinite, size > 0, width.isFinite, width > 0, height.isFinite, height > 0 else { return size }
        if let count = cellCount(for: size, width: width, height: height), count <= maxCells {
            return size
        }
        // Area-based estimate (each hex covers √3·s × 1.5·s), then step up to absorb the
        // partial rows/columns at the edges.
        var fitted = max(size, sqrt(width * height / (Double(maxCells) * sqrt(3) * 1.5)))
        for _ in 0..<200 {
            if let count = cellCount(for: fitted, width: width, height: height), count <= maxCells {
                return fitted.rounded(.up)
            }
            fitted *= 1.02
        }
        return fitted.rounded(.up)
    }

    static func grid(for size: Double, in rect: CGRect) -> [MapEntryModel] {
        // A zero/negative size or non-finite/non-positive rect dimension (an
        // unvalidated decode or import) would otherwise divide by zero (`Int` of a
        // NaN/inf quotient traps) or produce an invalid `0..<rows` range. See
        // CODE_AUDIT_17 §5.16.
        guard let (columns, rows) = dimensions(for: size, width: rect.width, height: rect.height),
              let count = cellCount(for: size, width: rect.width, height: rect.height),
              count <= maxCells else { return [] }

        let hexWidth = sqrt(3) * size
        let hexHeight = 2 * size

        var hexes: [MapEntryModel] = []
        for row in 0..<rows {
            let offsetY = Double(row) * hexHeight - Double(row) * size / 2
            let offsetRow = (row % 2 != 0) ? -(hexWidth / 2) : 0
            for col in 0..<columns {
                let offsetX = Double(col) * hexWidth + offsetRow
                let coordinates = hexCorners(
                    at: CGPoint(x: offsetX, y: offsetY),
                    maxPoint: CGPoint(x: rect.width, y: rect.height),
                    size: size
                )
                hexes.append(
                    MapEntryModel(
                        id: UUID(),
                        name: "\(col) - \(row)",
                        content: "",
                        coordinates: coordinates,
                        isHexGrid: true,
                        displayState: DisplayStateMask.groupHidden.rawValue
                    )
                )
            }
        }
        return hexes
    }

    @MainActor
    static func replaceGrid(_ entries: [MapEntryModel], in model: MapModel) {
        model.entries.removeAll { $0.isHexGrid }
        model.entries.append(contentsOf: entries)
    }

    private static func hexCorners(at offset: CGPoint, maxPoint: CGPoint, size: Double) -> [CGPoint] {
        let width = sqrt(3) * size
        let height = 2 * size
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, 0), maxPoint.x), y: min(max(point.y, 0), maxPoint.y))
        }
        return [
            clamp(CGPoint(x: offset.x, y: offset.y)),
            clamp(CGPoint(x: offset.x + width / 2, y: offset.y - height / 4)),
            clamp(CGPoint(x: offset.x + width, y: offset.y)),
            clamp(CGPoint(x: offset.x + width, y: offset.y + size)),
            clamp(CGPoint(x: offset.x + width / 2, y: offset.y + 3 * height / 4)),
            clamp(CGPoint(x: offset.x, y: offset.y + size)),
        ]
    }
}
