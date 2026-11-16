// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d20")
struct TableDie20GeometryTests {
    @Test("There is one face for each number from 1 to 20")
    func twentyNumberedFaces() {
        #expect(TableDie20Geometry.faces.map(\.number) == Array(1 ... 20))
    }

    @Test("Opposite faces add up to twenty-one")
    func oppositeFacesAddUpToTwentyOne() {
        for face in TableDie20Geometry.faces {
            let opposite = TableDie20Geometry.face(number: 21 - face.number)
            #expect(opposite.map { simd_distance($0.normal, -face.normal) < 0.000_1 } == true)
        }
    }

    @Test("Every face is an equilateral triangle, wound counter-clockwise seen from outside, at half the display height from the center")
    func facesAreRegularTriangles() {
        for face in TableDie20Geometry.faces {
            #expect(face.corners.count == 3)
            let edges = (0 ..< 3).map { simd_distance(face.corners[$0], face.corners[($0 + 1) % 3]) }
            #expect(edges.allSatisfy { abs($0 - edges[0]) < 0.000_01 })
            for corner in face.corners {
                #expect(abs(simd_dot(corner, face.normal) - TableDie20Geometry.displayHeight / 2) < 0.000_01)
            }
            let turn = simd_cross(face.corners[1] - face.corners[0], face.corners[2] - face.corners[0])
            #expect(simd_dot(turn, face.normal) > 0)
        }
    }

    @Test("The twenty faces together make a closed solid: every corner is shared by five faces")
    func cornersAreSharedByFiveFaces() {
        let corners = TableDie20Geometry.faces.flatMap(\.corners)
        #expect(corners.count == 60)
        for corner in corners {
            let shared = corners.filter { simd_distance($0, corner) < 0.000_01 }.count
            #expect(shared == 5)
        }
    }

    @Test("The die rests on a face as authored: face 1 up, so the bounds are as tall as the die stands")
    func authoredRestingOnAFace() {
        let ys = TableDie20Geometry.faces.flatMap(\.corners).map(\.y)
        #expect(simd_distance(TableDie20Geometry.faces[0].normal, [0, 1, 0]) < 0.000_1)
        #expect(abs((ys.max() ?? 0) - TableDie20Geometry.displayHeight / 2) < 0.000_01)
        #expect(abs((ys.min() ?? 0) + TableDie20Geometry.displayHeight / 2) < 0.000_01)
    }

    @Test("The numbers are arranged like the photographed d20: neighbors of 20 and of 1")
    func arrangementOfTheScannedDie() {
        func neighbors(of number: Int) -> Set<Int> {
            guard let face = TableDie20Geometry.face(number: number) else { return [] }
            return Set(TableDie20Geometry.faces.filter { other in
                other.number != number
                    && other.corners.filter { corner in face.corners.contains { simd_distance($0, corner) < 0.000_01 } }.count == 2
            }.map(\.number))
        }
        // Measured from the scan of the d20 the table used before.
        #expect(neighbors(of: 20) == [2, 8, 14])
        #expect(neighbors(of: 1) == [7, 13, 19])
        #expect(neighbors(of: 13) == [1, 5, 11])
    }

    @Test("Every face keeps inside its own atlas cell, with its numeral at the center of the triangle")
    func atlasTriangles() {
        for face in TableDie20Geometry.faces {
            let index = face.number - 1
            let cell = SIMD2<Float>(Float(index % 5), Float(index / 5))
            let lower = SIMD2<Float>(cell.x / 5, cell.y / 4)
            let upper = SIMD2<Float>((cell.x + 1) / 5, (cell.y + 1) / 4)
            let triangle = TableDie20Geometry.atlasTriangle(for: face)
            #expect(triangle.coordinates.count == 3)
            for point in triangle.coordinates + [triangle.center] {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
            // The first corner is the top one.
            #expect(triangle.coordinates[0].y < triangle.center.y)
            #expect(simd_distance(triangle.center, triangle.coordinates.reduce(.zero, +) / 3) < 0.000_1)
        }
    }

    @Test("6 and 9 are underlined, the other numbers are not")
    func underlines() {
        #expect((1 ... 20).filter { TableDie20Geometry.isUnderlined(number: $0) } == [6, 9])
    }
}
#endif
