// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d20 on the 3D table is generated like the other polyhedral dice: a regular icosahedron of
// twenty triangular faces, each with its own vertices (flat shading) and its own cell of a 5 × 4
// texture atlas, in which the numeral of the face is drawn. The numbers are arranged like the ones
// of the photographed d20 the table used before (measured from its scan), so the same numbers
// neighbor each other and opposite faces add up to twenty-one. Pure, so it is unit-tested on iOS:
// the rolled value must land face up, so the normal of each numbered face is what
// `Die20.restingOrientation` rests on.

enum TableDie20Geometry {
    /// Distance between opposite faces, the height the d20 presents on the table.
    static let displayHeight: Float = 0.0375

    /// A numbered triangular face; its corners wind counter-clockwise seen from outside, the first
    /// being the one the numeral's top points to.
    struct Face: Equatable {
        let number: Int
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
    }

    private static let phi = (1 + Float(5).squareRoot()) / 2

    /// The corners of an icosahedron with edge length 2: (0, ±1, ±φ), (±1, ±φ, 0) and (±φ, 0, ±1).
    static let unitCorners: [SIMD3<Float>] = [
        [0, 1, phi], [0, -1, phi], [0, 1, -phi], [0, -1, -phi],
        [1, phi, 0], [-1, phi, 0], [1, -phi, 0], [-1, -phi, 0],
        [phi, 0, 1], [phi, 0, -1], [-phi, 0, 1], [-phi, 0, -1]
    ]

    /// The three corners (indices into `unitCorners`) of the face with each number, 1 to 20.
    /// Matched to the measured normals of the scanned d20 within about one degree.
    static let cornersOfNumber: [Int: [Int]] = [
        1: [0, 1, 8], 2: [2, 3, 9], 3: [1, 7, 10], 4: [2, 4, 5], 5: [4, 8, 9],
        6: [5, 10, 11], 7: [1, 6, 8], 8: [3, 7, 11], 9: [0, 5, 10], 10: [3, 6, 7],
        11: [0, 4, 5], 12: [3, 6, 9], 13: [0, 4, 8], 14: [2, 5, 11], 15: [6, 8, 9],
        16: [7, 10, 11], 17: [1, 6, 7], 18: [2, 4, 9], 19: [0, 1, 10], 20: [2, 3, 11]
    ]

    /// The faces by number, 1 to 20, sized so that the distance between opposite faces is
    /// `displayHeight`, and turned so that face 1 lies flat and faces up. TabletopKit rests a die at
    /// the bottom of its entity's bounds, taken in the orientation the mesh is authored in, so that
    /// orientation has to be one the die rests in — a face down — or the die floats above the table
    /// by the difference.
    static let faces: [Face] = {
        func faceNormal(_ corners: [SIMD3<Float>]) -> SIMD3<Float> {
            simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
        }
        // The distance from the center to a face, for the corners as they are.
        let first = (cornersOfNumber[1] ?? []).map { unitCorners[$0] }
        let inradius = simd_dot(first[0], faceNormal(first))
        let scale = displayHeight / (2 * abs(inradius))

        let raw = (1 ... 20).map { number -> Face in
            var corners = (cornersOfNumber[number] ?? []).map { unitCorners[$0] }
            var normal = faceNormal(corners)
            // The normal points away from the center; a face wound the other way round is flipped.
            if simd_dot(normal, corners[0]) < 0 {
                corners.swapAt(1, 2)
                normal = -normal
            }
            return Face(number: number, corners: corners.map { $0 * scale }, normal: normal)
        }
        let turn = simd_quatf(from: raw[0].normal, to: SIMD3<Float>(0, 1, 0))
        return raw.map { face in
            Face(number: face.number, corners: face.corners.map { turn.act($0) }, normal: turn.act(face.normal))
        }
    }()

    static func face(number: Int) -> Face? {
        faces.first { $0.number == number }
    }

    // MARK: Labels

    /// Whether the label gets an underline (the art has a dot after them), so that it can't be
    /// read upside down.
    static func isUnderlined(number: Int) -> Bool {
        number == 6 || number == 9
    }

    // MARK: Texture atlas

    static let atlasColumns = 5
    static let atlasRows = 4
    private static let cellFill: Float = 0.94

    /// A face's triangle on the atlas.
    typealias AtlasTriangle = TableDieFaceAtlas.Layout

    /// The triangle of a face in its atlas cell: the face seen from outside with its first corner
    /// up, scaled to fill the cell, so the numeral reads the right way round.
    static func atlasTriangle(for face: Face) -> AtlasTriangle {
        let index = face.number - 1
        let center = face.corners.reduce(.zero, +) / 3
        return TableDieFaceAtlas.layout(
            corners: face.corners,
            normal: face.normal,
            up: face.corners[0] - center,
            cell: (index % atlasColumns, index / atlasColumns),
            columns: atlasColumns,
            rows: atlasRows,
            fill: cellFill
        )
    }
}
#endif
