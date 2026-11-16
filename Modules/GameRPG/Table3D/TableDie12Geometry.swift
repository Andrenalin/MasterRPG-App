// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d12 on the 3D table is generated like the d8 and d10: a regular dodecahedron of twelve
// pentagonal faces, each with its own vertices (flat shading) and its own cell of a 4 × 3 texture
// atlas, in which the numeral of the face is drawn. Pure, so it is unit-tested on iOS: the rolled
// value must land face up, so the normal of each numbered face is what `Die12.restingOrientation`
// rests on.

enum TableDie12Geometry {
    /// Distance between opposite faces, the height the d12 presents on the table.
    static let displayHeight: Float = 0.033

    /// A numbered pentagonal face; its corners wind counter-clockwise seen from outside, the first
    /// being the one the numeral's top points to.
    struct Face: Equatable {
        let number: Int
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
    }

    private static let phi = (1 + Float(5).squareRoot()) / 2

    /// The corners of a dodecahedron with edge length 2/φ: the cube's corners and the corners
    /// (0, ±φ, ±1/φ), (±1/φ, 0, ±φ) and (±φ, ±1/φ, 0).
    private static let unitCorners: [SIMD3<Float>] = {
        var corners: [SIMD3<Float>] = []
        for x: Float in [-1, 1] {
            for y: Float in [-1, 1] {
                for z: Float in [-1, 1] {
                    corners.append([x, y, z])
                }
            }
        }
        for a: Float in [-1, 1] {
            for b: Float in [-1, 1] {
                corners.append([0, a * phi, b / phi])
                corners.append([a / phi, 0, b * phi])
                corners.append([a * phi, b / phi, 0])
            }
        }
        return corners
    }()

    /// The six face directions that stand for a pair of opposite faces. A face is numbered `k + 1`
    /// and the one opposite it `12 − k`, so opposite faces add up to thirteen.
    private static let representatives: [SIMD3<Float>] = [
        [0, 1, phi], [0, -1, phi], [1, phi, 0], [-1, phi, 0], [phi, 0, 1], [phi, 0, -1]
    ]

    /// The faces by number, 1 to 12, sized so that the distance between opposite faces is `displayHeight`.
    static let faces: [Face] = {
        var numbered: [(number: Int, normal: SIMD3<Float>)] = []
        for (k, direction) in representatives.enumerated() {
            numbered.append((k + 1, simd_normalize(direction)))
            numbered.append((12 - k, simd_normalize(-direction)))
        }
        // The distance from the center to a face, for the corners as they are.
        let inradius = unitCorners
            .map { simd_dot($0, simd_normalize(representatives[0])) }
            .max() ?? 1
        let scale = displayHeight / (2 * inradius)

        let faces = numbered.sorted { $0.number < $1.number }.map { number, normal in
            // The face's five corners are the ones farthest along its normal.
            let best = unitCorners.map { simd_dot($0, normal) }.max() ?? 0
            let onFace = unitCorners.filter { simd_dot($0, normal) > best - 0.000_1 }
            let center = onFace.reduce(.zero, +) / Float(onFace.count)
            // Around the normal, counter-clockwise seen from outside: starting at any corner,
            // by the angle in the plane of the face.
            let first = simd_normalize(onFace[0] - center)
            let second = simd_cross(normal, first)
            let ordered = onFace.sorted {
                angle(of: $0 - center, first, second) < angle(of: $1 - center, first, second)
            }
            return Face(number: number, corners: ordered.map { $0 * scale }, normal: normal)
        }
        return restingOnFaceOne(faces)
    }()

    /// Turns the die so that face 1 lies flat and faces up. TabletopKit rests a die at the bottom
    /// of its entity's bounds, taken in the orientation the mesh is authored in, so that
    /// orientation has to be one the die rests in — a face down, like the d20 asset's — or the
    /// die floats above the table by the difference.
    private static func restingOnFaceOne(_ faces: [Face]) -> [Face] {
        let turn = simd_quatf(from: faces[0].normal, to: SIMD3<Float>(0, 1, 0))
        return faces.map { face in
            Face(number: face.number, corners: face.corners.map { turn.act($0) }, normal: turn.act(face.normal))
        }
    }

    private static func angle(of vector: SIMD3<Float>, _ first: SIMD3<Float>, _ second: SIMD3<Float>) -> Float {
        atan2(simd_dot(vector, second), simd_dot(vector, first))
    }

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

    static let atlasColumns = 4
    static let atlasRows = 3
    private static let cellFill: Float = 0.92

    /// A face's pentagon on the atlas.
    typealias AtlasPentagon = TableDieFaceAtlas.Layout

    /// The pentagon of a face in its atlas cell: the face seen from outside with its first corner
    /// up, scaled to fill the cell, so the numeral reads the right way round.
    static func atlasPentagon(for face: Face) -> AtlasPentagon {
        let index = face.number - 1
        let center = face.corners.reduce(.zero, +) / Float(face.corners.count)
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
