// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d6 and the d3 on the 3D table are generated like the other dice: a cube whose six faces each
// have their own vertices (flat shading) and their own cell of a 3 × 2 texture atlas. The d6 has
// its pips drawn in the cells, the d3 the numbers 1, 2 and 3 (see `TableDie3Layout`), so both share
// this mesh. Pure, so it is unit-tested on iOS: the rolled value must land face up, so the normal of
// each numbered face is what `Die6.restingOrientation` rests on.

enum TableDie6Geometry {
    /// The edge of the cube, which is the height it presents on the table.
    static let displayHeight: Float = 0.03

    /// A face, known by the number of pips it has on the d6. Its corners wind counter-clockwise
    /// seen from outside, starting at the top left with `up` up.
    struct Face: Equatable {
        let number: Int
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
        /// Where the top of the pip pattern or numeral points to, in the plane of the face.
        let up: SIMD3<Float>
    }

    /// The faces by number. Opposite faces add up to seven, as on any standard d6. The cube is
    /// authored with 6 up, 2 on the right and 3 at the front, like the d6 asset it replaces.
    static let faces: [Face] = [
        face(number: 1, normal: [0, -1, 0], up: [0, 0, -1]),
        face(number: 2, normal: [1, 0, 0], up: [0, 1, 0]),
        face(number: 3, normal: [0, 0, 1], up: [0, 1, 0]),
        face(number: 4, normal: [0, 0, -1], up: [0, 1, 0]),
        face(number: 5, normal: [-1, 0, 0], up: [0, 1, 0]),
        face(number: 6, normal: [0, 1, 0], up: [0, 0, -1])
    ]

    private static func face(number: Int, normal: SIMD3<Float>, up: SIMD3<Float>) -> Face {
        // Seen from outside, with `up` up, to the right is `up × normal`.
        let right = simd_cross(up, normal)
        let half = displayHeight / 2
        let center = normal * half
        let corners = [
            center - right * half + up * half,
            center - right * half - up * half,
            center + right * half - up * half,
            center + right * half + up * half
        ]
        return Face(number: number, corners: corners, normal: normal, up: up)
    }

    static func face(number: Int) -> Face? {
        faces.first { $0.number == number }
    }

    // MARK: Pips

    /// Where the pips of a face with this many pips stand, relative to the center of the face in
    /// parts of its width (x to the right, y up). Standard d6 pattern.
    static func pipOffsets(for number: Int) -> [SIMD2<Float>] {
        let near: Float = 0.26
        let corners: [SIMD2<Float>] = [[-near, near], [near, -near], [-near, -near], [near, near]]
        switch number {
            case 1: return [.zero]
            case 2: return Array(corners.prefix(2))
            case 3: return Array(corners.prefix(2)) + [.zero]
            case 4: return corners
            case 5: return corners + [.zero]
            case 6: return [-near, 0, near].flatMap { y in [SIMD2<Float>(-near, y), SIMD2<Float>(near, y)] }
            default: return []
        }
    }

    /// The radius of a pip in parts of the width of a face.
    static let pipRadius: Float = 0.09

    // MARK: Texture atlas

    static let atlasColumns = 3
    static let atlasRows = 2
    private static let cellFill: Float = 0.94

    /// A face in its atlas cell.
    typealias AtlasSquare = TableDieFaceAtlas.Layout

    /// The face in its atlas cell: seen from outside with `up` up and scaled to fill the cell, so
    /// pips and numerals drawn upright in the cell read the right way round.
    static func atlasSquare(for face: Face) -> AtlasSquare {
        let index = face.number - 1
        return TableDieFaceAtlas.layout(
            corners: face.corners,
            normal: face.normal,
            up: face.up,
            cell: (index % atlasColumns, index / atlasColumns),
            columns: atlasColumns,
            rows: atlasRows,
            fill: cellFill
        )
    }

    /// The width of a face in the atlas, in atlas coordinates (0…1) along x.
    static let faceWidthInAtlas = cellFill / Float(atlasColumns)
}
#endif
