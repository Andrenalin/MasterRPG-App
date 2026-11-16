// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// How a face of a die generated in code (`TableDie10Geometry`, `TableDie12Geometry`) lies in its
// cell of the texture atlas. Pure, so it is unit-tested on iOS.

enum TableDieFaceAtlas {
    /// A face on the atlas.
    struct Layout: Equatable {
        /// The atlas coordinates (0…1, y down) of the face's corners, in the order given.
        let coordinates: [SIMD2<Float>]
        /// Where the numeral stands: the centroid of the face.
        let center: SIMD2<Float>
    }

    /// The face seen from outside with `up` up, scaled to fill `fill` of its cell, so a numeral
    /// drawn upright in the cell reads the right way round with its top towards `up`.
    /// - Parameters:
    ///   - corners: The face's corners, counter-clockwise seen from outside.
    ///   - normal: The outward normal of the face.
    ///   - up: Where the top of the numeral points, in the plane of the face.
    ///   - cell: The cell's column and row.
    static func layout(
        corners: [SIMD3<Float>],
        normal: SIMD3<Float>,
        up: SIMD3<Float>,
        cell: (column: Int, row: Int),
        columns: Int,
        rows: Int,
        fill: Float
    ) -> Layout {
        let up = simd_normalize(up)
        // Seen from outside, with `up` up, to the right is `up × normal`.
        let right = simd_cross(up, normal)
        let origin = corners[0]
        let flat = corners.map { SIMD2<Float>(simd_dot($0 - origin, right), simd_dot($0 - origin, up)) }

        let lower = SIMD2<Float>(flat.map(\.x).min() ?? 0, flat.map(\.y).min() ?? 0)
        let upper = SIMD2<Float>(flat.map(\.x).max() ?? 0, flat.map(\.y).max() ?? 0)
        let middle = (lower + upper) / 2
        let scale = fill / max(upper.x - lower.x, upper.y - lower.y)

        let cellOrigin = SIMD2<Float>(Float(cell.column), Float(cell.row))
        let size = SIMD2<Float>(Float(columns), Float(rows))
        func atlas(_ point: SIMD2<Float>) -> SIMD2<Float> {
            let inCell = SIMD2<Float>(0.5 + (point.x - middle.x) * scale, 0.5 - (point.y - middle.y) * scale)
            return (cellOrigin + inCell) / size
        }

        // The area centroid of the face.
        var area: Float = 0
        var centroid = SIMD2<Float>.zero
        for i in flat.indices {
            let a = flat[i]
            let b = flat[(i + 1) % flat.count]
            let cross = a.x * b.y - b.x * a.y
            area += cross
            centroid += (a + b) * cross
        }
        centroid /= 3 * area
        return Layout(coordinates: flat.map(atlas), center: atlas(centroid))
    }
}
#endif
