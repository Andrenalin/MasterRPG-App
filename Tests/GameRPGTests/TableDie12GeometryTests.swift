// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d12")
struct TableDie12GeometryTests {
    @Test("There is one face for each number from 1 to 12")
    func twelveNumberedFaces() {
        #expect(TableDie12Geometry.faces.map(\.number) == Array(1 ... 12))
    }

    @Test("Opposite faces add up to thirteen")
    func oppositeFacesAddUpToThirteen() {
        for face in TableDie12Geometry.faces {
            let opposite = TableDie12Geometry.face(number: 13 - face.number)
            #expect(opposite.map { simd_distance($0.normal, -face.normal) < 0.000_1 } == true)
        }
    }

    @Test("Every face is a regular pentagon, wound counter-clockwise seen from outside, at half the display height from the center")
    func facesAreRegularPentagons() {
        for face in TableDie12Geometry.faces {
            #expect(face.corners.count == 5)
            let edges = (0 ..< 5).map { simd_distance(face.corners[$0], face.corners[($0 + 1) % 5]) }
            #expect(edges.allSatisfy { abs($0 - edges[0]) < 0.000_01 })
            for corner in face.corners {
                #expect(abs(simd_dot(corner, face.normal) - TableDie12Geometry.displayHeight / 2) < 0.000_01)
            }
            // Counter-clockwise: each corner turns the same way, outward.
            for i in 0 ..< 5 {
                let a = face.corners[i]
                let b = face.corners[(i + 1) % 5]
                let c = face.corners[(i + 2) % 5]
                #expect(simd_dot(simd_cross(b - a, c - b), face.normal) > 0)
            }
        }
    }

    @Test("The twelve faces together make a closed solid: every corner is shared by three faces")
    func cornersAreSharedByThreeFaces() {
        let corners = TableDie12Geometry.faces.flatMap(\.corners)
        #expect(corners.count == 60)
        for corner in corners {
            let shared = corners.filter { simd_distance($0, corner) < 0.000_01 }.count
            #expect(shared == 3)
        }
    }

    @Test("The die rests on a face as authored: face 1 up, so the bounds are as tall as the die stands")
    func authoredRestingOnAFace() {
        let ys = TableDie12Geometry.faces.flatMap(\.corners).map(\.y)
        #expect(simd_distance(TableDie12Geometry.faces[0].normal, [0, 1, 0]) < 0.000_1)
        #expect(abs((ys.max() ?? 0) - TableDie12Geometry.displayHeight / 2) < 0.000_01)
        #expect(abs((ys.min() ?? 0) + TableDie12Geometry.displayHeight / 2) < 0.000_01)
    }

    @Test("Every pentagon keeps inside its own atlas cell, with its first corner on top")
    func atlasPentagonsStayInTheirCells() {
        for face in TableDie12Geometry.faces {
            let index = face.number - 1
            let cell = SIMD2<Float>(Float(index % 4), Float(index / 4))
            let lower = cell / SIMD2<Float>(4, 3)
            let upper = (cell + 1) / SIMD2<Float>(4, 3)
            let pentagon = TableDie12Geometry.atlasPentagon(for: face)
            #expect(pentagon.coordinates.count == 5)
            for point in pentagon.coordinates + [pentagon.center] {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
            // On the image (y down) the first corner is the highest one.
            #expect(pentagon.coordinates.dropFirst().allSatisfy { $0.y > pentagon.coordinates[0].y })
        }
    }

    @Test("6 and 9 are underlined, so they can be told apart")
    func underlines() {
        #expect((1 ... 12).filter { TableDie12Geometry.isUnderlined(number: $0) } == [6, 9])
    }
}
#endif
