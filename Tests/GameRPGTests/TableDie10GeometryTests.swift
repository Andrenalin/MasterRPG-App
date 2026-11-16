// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d10")
struct TableDie10GeometryTests {
    @Test("There is one face for each number from 1 to 10")
    func tenNumberedFaces() {
        #expect(TableDie10Geometry.faces.map(\.number) == Array(1 ... 10))
    }

    @Test("Opposite faces add up to eleven")
    func oppositeFacesAddUpToEleven() {
        for face in TableDie10Geometry.faces {
            let opposite = TableDie10Geometry.face(number: 11 - face.number)
            #expect(opposite.map { simd_distance($0.normal, -face.normal) < 0.000_1 } == true)
        }
    }

    @Test("Each kite is flat, wound counter-clockwise seen from outside, and the die is sized by its faces")
    func kitesAreFlatAndOutward() {
        for face in TableDie10Geometry.faces {
            let normal = face.normal
            #expect(abs(simd_length(normal) - 1) < 0.000_1)
            // All four corners lie in one plane, at half the display height from the center.
            for corner in face.corners {
                #expect(abs(simd_dot(corner, normal) - TableDie10Geometry.displayHeight / 2) < 0.000_01)
            }
            // Counter-clockwise: both triangles of the kite face outward.
            let first = simd_cross(face.corners[1] - face.corners[0], face.corners[2] - face.corners[0])
            let second = simd_cross(face.corners[2] - face.corners[0], face.corners[3] - face.corners[0])
            #expect(simd_dot(first, normal) > 0)
            #expect(simd_dot(second, normal) > 0)
        }
    }

    @Test("A kite has the symmetry of a kite: two pairs of equal edges meeting at the apex and the opposite corner")
    func kitesAreKites() {
        for face in TableDie10Geometry.faces {
            let c = face.corners
            #expect(abs(simd_distance(c[0], c[1]) - simd_distance(c[0], c[3])) < 0.000_01)
            #expect(abs(simd_distance(c[2], c[1]) - simd_distance(c[2], c[3])) < 0.000_01)
        }
    }

    @Test("The die rests on a face as authored: face 1 up, so the bounds are as tall as the die stands")
    func authoredRestingOnAFace() {
        let ys = TableDie10Geometry.faces.flatMap(\.corners).map(\.y)
        #expect(simd_distance(TableDie10Geometry.faces[0].normal, [0, 1, 0]) < 0.000_1)
        #expect(abs((ys.max() ?? 0) - TableDie10Geometry.displayHeight / 2) < 0.000_01)
        #expect(abs((ys.min() ?? 0) + TableDie10Geometry.displayHeight / 2) < 0.000_01)
    }

    @Test("Every kite keeps inside its own atlas cell, and its numeral inside the kite's bounds")
    func atlasKitesStayInTheirCells() {
        for face in TableDie10Geometry.faces {
            let index = face.number - 1
            let cell = SIMD2<Float>(Float(index % 5), Float(index / 5))
            let lower = cell / SIMD2<Float>(5, 2)
            let upper = (cell + 1) / SIMD2<Float>(5, 2)
            let kite = TableDie10Geometry.atlasKite(for: face)
            #expect(kite.coordinates.count == 4)
            for point in kite.coordinates + [kite.center] {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
            // The apex is the top of the kite on the image (y down).
            #expect(kite.coordinates[0].y < kite.coordinates[2].y)
        }
    }

    @Test("A d10 prints 1 to 9 and a 0 for its tenth face; the tens dice 10 to 90 and 00")
    func labels() {
        #expect((1 ... 10).map { TableDie10Geometry.label(forFace: $0, percentile: false) }
            == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        #expect((1 ... 10).map { TableDie10Geometry.label(forFace: $0, percentile: true) }
            == ["10", "20", "30", "40", "50", "60", "70", "80", "90", "00"])
        #expect(["C", "D", "F"].allSatisfy { TableDie10Geometry.isPercentile(code: $0) })
        #expect(["A", "B", "E", "G"].allSatisfy { !TableDie10Geometry.isPercentile(code: $0) })
    }

    @Test("6 and 9 are underlined, so they can be told apart")
    func underlines() {
        #expect(["6", "9", "60", "90"].allSatisfy { TableDie10Geometry.isUnderlined(label: $0) })
        #expect(!["0", "1", "8", "00", "10"].contains { TableDie10Geometry.isUnderlined(label: $0) })
    }
}
#endif
