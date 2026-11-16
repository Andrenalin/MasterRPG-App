// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d8 on the 3D table is generated, not loaded: a regular octahedron whose eight faces each
// have their own corner vertices (flat shading) and their own cell of a 4 × 2 texture atlas, in
// which the numeral of the face is drawn. Pure, so it is unit-tested on iOS: the rolled value
// must land face up, so the normal of each numbered face is what `Die8.restingOrientation` rests on.

enum TableDie8Geometry {
    /// Distance between opposite faces, the height the d8 presents on the table.
    static let displayHeight: Float = 0.03
    /// Distance from the center to a corner: a regular octahedron with that face-to-face distance.
    static let circumradius: Float = displayHeight * Float(3).squareRoot() / 2

    /// Turns the octahedron so that face 1 lies flat and faces up. TabletopKit rests a die at the
    /// bottom of its entity's bounds, taken in the orientation the mesh is authored in, so that
    /// orientation has to be one the die rests in — a face down, like the d20 asset's — or the
    /// die floats above the table by the difference. See `Die8Assets.meshResource`.
    private static let alignment = simd_quatf(from: simd_normalize(SIMD3<Float>(1, 1, 1)), to: SIMD3<Float>(0, 1, 0))

    /// A numbered face: the octant of its corners is `signs`, as the corners are `(sx·r, 0, 0)`,
    /// `(0, sy·r, 0)` and `(0, 0, sz·r)` before the die is turned to rest on a face.
    struct Face: Equatable {
        let number: Int
        let signs: SIMD3<Float>

        var normal: SIMD3<Float> {
            TableDie8Geometry.alignment.act(signs / Float(3).squareRoot())
        }

        /// The three corners, counter-clockwise seen from outside.
        func corners(circumradius r: Float) -> [SIMD3<Float>] {
            let a = SIMD3<Float>(signs.x * r, 0, 0)
            let b = SIMD3<Float>(0, signs.y * r, 0)
            let c = SIMD3<Float>(0, 0, signs.z * r)
            // A mirrored octant winds the other way round.
            let corners = signs.x * signs.y * signs.z > 0 ? [a, b, c] : [a, c, b]
            return corners.map { TableDie8Geometry.alignment.act($0) }
        }
    }

    /// The faces by number. Opposite faces add up to nine, as on any standard d8.
    static let faces: [Face] = [
        Face(number: 1, signs: [1, 1, 1]),
        Face(number: 2, signs: [-1, 1, 1]),
        Face(number: 3, signs: [1, -1, 1]),
        Face(number: 4, signs: [1, 1, -1]),
        Face(number: 5, signs: [-1, -1, 1]),
        Face(number: 6, signs: [-1, 1, -1]),
        Face(number: 7, signs: [1, -1, -1]),
        Face(number: 8, signs: [-1, -1, -1])
    ]

    static func face(number: Int) -> Face? {
        faces.first { $0.number == number }
    }

    // MARK: Texture atlas

    static let atlasColumns = 4
    static let atlasRows = 2

    /// The corners of a face's triangle in its atlas cell, in cell coordinates 0…1 with y down
    /// like an image: the first is the top corner, the others follow counter-clockwise.
    static let cellTriangle: [SIMD2<Float>] = [[0.5, 0.10], [0.04, 0.897], [0.96, 0.897]]

    /// Where the numeral of a face stands in its cell: the center of the triangle.
    static let cellCenter = SIMD2<Float>(0.5, 0.631)

    /// The atlas coordinates (0…1, y down) of a face's three corners, in the order `corners` has
    /// them. The corners already wind counter-clockwise seen from outside, like the cell's
    /// triangle on the image, so the numeral reads the right way round on every face.
    static func atlasCoordinates(for face: Face) -> [SIMD2<Float>] {
        let index = face.number - 1
        let origin = SIMD2<Float>(Float(index % atlasColumns), Float(index / atlasColumns))
        let size = SIMD2<Float>(Float(atlasColumns), Float(atlasRows))
        return cellTriangle.map { (origin + $0) / size }
    }
}
#endif
