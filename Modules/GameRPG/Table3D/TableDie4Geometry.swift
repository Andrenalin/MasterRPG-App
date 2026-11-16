// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d4 on the 3D table is generated like the other polyhedral dice: a regular tetrahedron with
// its own vertices per face (flat shading) and its own cell of a 2 × 2 texture atlas. It is the
// d4 of the 2D art (`D4<code>-<number>`): every corner carries a number, printed on each of the
// three faces that meet there with its top towards that corner, and the number rolled is the one
// at the corner that points up. Pure, so it is unit-tested on iOS: the rolled value must land up,
// so the direction of each numbered corner is what `Die4.restingOrientation` rests on.

enum TableDie4Geometry {
    /// The height the d4 stands on the table: from a face to the corner opposite it.
    static let displayHeight: Float = 0.03

    /// A face of the tetrahedron, the one opposite the corner `opposite`; its corners wind
    /// counter-clockwise seen from outside.
    struct Face: Equatable {
        /// The number of the corner opposite the face, 1 to 4: this face is the one the die rests
        /// on when that number is up.
        let opposite: Int
        let corners: [SIMD3<Float>]
        /// The number printed at each corner, in the order of `corners`.
        let numbers: [Int]
        let normal: SIMD3<Float>
    }

    /// The directions of the four corners, number 1 first: a regular tetrahedron, turned so that
    /// corner 1 points up. TabletopKit rests a die at the bottom of its entity's bounds, taken in
    /// the orientation the mesh is authored in, so that orientation has to be one the die rests in
    /// — a face down, like the d20 asset's — or the die floats above the table by the difference.
    /// With the center of the die at the entity's origin, every face is the same distance from it,
    /// so the die rests at the right height in each orientation.
    static let cornerDirections: [SIMD3<Float>] = {
        let raw: [SIMD3<Float>] = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]]
            .map { simd_normalize($0) }
        let turn = simd_quatf(from: raw[0], to: SIMD3<Float>(0, 1, 0))
        return raw.map { turn.act($0) }
    }()

    /// The distance from the center to a corner, for a die standing `displayHeight` tall: the
    /// center is a quarter of the height above the face.
    static let circumradius: Float = displayHeight * 3 / 4

    static func direction(ofNumber number: Int) -> SIMD3<Float>? {
        cornerDirections.indices.contains(number - 1) ? cornerDirections[number - 1] : nil
    }

    /// The faces, by the number of the corner opposite them.
    static let faces: [Face] = (0 ..< 4).map { opposite in
        let others = (0 ..< 4).filter { $0 != opposite }
        var corners = others.map { cornerDirections[$0] * circumradius }
        var numbers = others.map { $0 + 1 }
        let normal = -cornerDirections[opposite]
        if simd_dot(simd_cross(corners[1] - corners[0], corners[2] - corners[0]), normal) < 0 {
            corners.swapAt(1, 2)
            numbers.swapAt(1, 2)
        }
        return Face(opposite: opposite + 1, corners: corners, numbers: numbers, normal: normal)
    }

    // MARK: Texture atlas

    static let atlasColumns = 2
    static let atlasRows = 2
    private static let cellFill: Float = 0.94
    /// How far from the center of a face towards a corner its number stands, as a part of the way.
    private static let numeralReach: Float = 0.5

    /// A number printed on a face.
    struct Numeral: Equatable {
        let number: Int
        /// The atlas coordinates (0…1, y down) of its center.
        let center: SIMD2<Float>
        /// Where its top points to on the atlas (y down): from the center of the face to the corner.
        let direction: SIMD2<Float>
    }

    /// A face in its atlas cell and the three numbers on it.
    struct AtlasFace: Equatable {
        let coordinates: [SIMD2<Float>]
        let numerals: [Numeral]
    }

    /// The face in its atlas cell: seen from outside with its first corner up and scaled to fill
    /// the cell, each corner's number inside the triangle, upright towards that corner.
    static func atlasFace(for face: Face) -> AtlasFace {
        let index = face.opposite - 1
        let center3D = face.corners.reduce(.zero, +) / 3
        let layout = TableDieFaceAtlas.layout(
            corners: face.corners,
            normal: face.normal,
            up: face.corners[0] - center3D,
            cell: (index % atlasColumns, index / atlasColumns),
            columns: atlasColumns,
            rows: atlasRows,
            fill: cellFill
        )
        let numerals = zip(layout.coordinates, face.numbers).map { corner, number in
            let towards = corner - layout.center
            return Numeral(number: number, center: layout.center + towards * numeralReach, direction: towards)
        }
        return AtlasFace(coordinates: layout.coordinates, numerals: numerals)
    }
}
#endif
