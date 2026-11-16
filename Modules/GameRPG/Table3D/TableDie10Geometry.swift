// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The d10 on the 3D table is generated like the d8: a pentagonal trapezohedron of ten kite
// faces, each with its own vertices (flat shading) and its own cell of a 5 × 2 texture atlas,
// in which the numeral of the face is drawn. Pure, so it is unit-tested on iOS: the rolled
// value must land face up, so the normal of each numbered face is what `Die10.restingOrientation`
// rests on.

enum TableDie10Geometry {
    /// Distance between opposite faces, the height the d10 presents on the table. A d10 is
    /// wider than that — about 1.5 times — so this is chosen for a die about as big as the d8.
    static let displayHeight: Float = 0.03

    /// A numbered kite face. `corners[0]` is the apex of the die the kite belongs to and
    /// `corners[2]` the corner opposite it; the corners wind counter-clockwise seen from outside.
    struct Face: Equatable {
        let number: Int
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
    }

    // MARK: Shape

    /// A shape with the ring of ten corners on the unit circle. The corners alternate between
    /// `ringHeight` above and below the middle, and the apexes are placed so that each kite is flat:
    /// seen from the side, an apex, the midpoint between two upper corners and the lower corner
    /// between them must lie on one line, which gives `apexHeight = ringHeight (1 + c) / (1 − c)`
    /// for `c = cos 36°`.
    private static let ringHeight: Float = 0.1
    private static let apexHeight: Float = ringHeight * (1 + cos(Float.pi / 5)) / (1 - cos(Float.pi / 5))

    private static func ring(_ index: Int) -> SIMD3<Float> {
        let angle = Float(index) * .pi / 5
        let height = index.isMultiple(of: 2) ? ringHeight : -ringHeight
        return [cos(angle), height, sin(angle)]
    }

    /// The faces by number, 1 to 10; opposite faces add up to eleven. Sized so that the distance
    /// between opposite faces is `displayHeight`.
    static let faces: [Face] = {
        let top = SIMD3<Float>(0, apexHeight, 0)
        let bottom = SIMD3<Float>(0, -apexHeight, 0)
        var unit: [(number: Int, corners: [SIMD3<Float>])] = []
        for j in 0 ..< 5 {
            // The upper kites: the top apex, two upper corners, and the lower corner between them.
            unit.append((j + 1, [top, ring(2 * j), ring(2 * j + 1), ring(2 * j + 2)]))
            // The lower kites mirror them, turned by 36°. The kite `m` lies opposite the upper kite
            // `(m + 3) % 5`, as the die is point-symmetric.
            let opposite = (j + 3) % 5
            unit.append((10 - opposite, [bottom, ring(2 * j + 1), ring(2 * j + 2), ring(2 * j + 3)]))
        }
        func outward(_ corners: [SIMD3<Float>]) -> [SIMD3<Float>] {
            let centroid = corners.reduce(.zero, +) / 4
            let normal = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
            // Reversing keeps the apex first and the opposite corner third.
            return simd_dot(normal, centroid) >= 0 ? corners : [corners[0], corners[3], corners[2], corners[1]]
        }
        let wound = unit.map { (number: $0.number, corners: outward($0.corners)) }
        let faceToFace = 2 * simd_dot(
            simd_normalize(simd_cross(wound[0].corners[1] - wound[0].corners[0], wound[0].corners[2] - wound[0].corners[0])),
            wound[0].corners[0]
        )
        let scale = displayHeight / faceToFace
        let scaled = wound.map { face in
            let corners = face.corners.map { $0 * scale }
            let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
            return Face(number: face.number, corners: corners, normal: normal)
        }
        .sorted { $0.number < $1.number }
        return restingOnFaceOne(scaled)
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

    static func face(number: Int) -> Face? {
        faces.first { $0.number == number }
    }

    // MARK: Labels

    /// The colour codes whose art is a tens die: its faces read 10 … 90 and 00 (see `D10C-…`).
    static func isPercentile(code: String) -> Bool {
        ["C", "D", "F"].contains(code)
    }

    /// What is printed on a face: a d10 has a 0 for its tenth face; a tens die has 00 for it and
    /// 10 … 90 for the others.
    static func label(forFace number: Int, percentile: Bool) -> String {
        let digit = number % 10
        return percentile ? String(digit * 10).leftPadded(to: 2) : String(digit)
    }

    /// Whether the label gets an underline, so that it can't be read upside down.
    static func isUnderlined(label: String) -> Bool {
        ["6", "9", "60", "90"].contains(label)
    }

    // MARK: Texture atlas

    static let atlasColumns = 5
    static let atlasRows = 2
    /// How much of its cell a kite fills.
    private static let cellFill: Float = 0.9

    /// A face's kite on the atlas.
    typealias AtlasKite = TableDieFaceAtlas.Layout

    /// The kite of a face in its atlas cell: the face seen from outside with its apex up, scaled
    /// to fill the cell, so the numeral reads the right way round with its top towards the apex.
    static func atlasKite(for face: Face) -> AtlasKite {
        let index = face.number - 1
        return TableDieFaceAtlas.layout(
            corners: face.corners,
            normal: face.normal,
            up: face.corners[0] - face.corners[2],
            cell: (index % atlasColumns, index / atlasColumns),
            columns: atlasColumns,
            rows: atlasRows,
            fill: cellFill
        )
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
#endif
