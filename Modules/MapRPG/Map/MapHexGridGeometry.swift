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
        guard requestedSize < 10 else { return requestedSize }
        let widthScale = model.width / (defaultHexesAcrossShortSide * sqrt(3))
        let heightScale = model.height / (defaultHexesAcrossShortSide * 1.5)
        return max(widthScale, heightScale)
    }

    /// Hard cap on the number of hex cells generated in one call — protects against an
    /// unvalidated, very large map dimension with a small scale producing hundreds of
    /// thousands of `MapEntryModel`s. See CODE_AUDIT_17 §5.16.
    private static let maxCells = 20_000

    static func grid(for size: Double, in rect: CGRect) -> [MapEntryModel] {
        // A zero/negative size or non-finite/non-positive rect dimension (an
        // unvalidated decode or import) would otherwise divide by zero (`Int` of a
        // NaN/inf quotient traps) or produce an invalid `0..<rows` range. See
        // CODE_AUDIT_17 §5.16.
        guard size.isFinite, size > 0,
              rect.width.isFinite, rect.width > 0,
              rect.height.isFinite, rect.height > 0 else { return [] }

        let hexWidth = sqrt(3) * size
        let hexHeight = 2 * size
        let columns = Int((rect.width + hexWidth / 2) / hexWidth) + 1
        let rows = Int((rect.height + size / 2) / (3 * size / 2)) + 1
        guard columns > 0, rows > 0, columns * rows <= maxCells else { return [] }

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
