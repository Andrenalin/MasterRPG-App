// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d8")
struct TableDie8GeometryTests {
    @Test("There is one face for each number from 1 to 8")
    func eightNumberedFaces() {
        #expect(TableDie8Geometry.faces.map(\.number) == Array(1 ... 8))
        #expect(Set(TableDie8Geometry.faces.map(\.signs)).count == 8)
    }

    @Test("Opposite faces add up to nine")
    func oppositeFacesAddUpToNine() {
        for face in TableDie8Geometry.faces {
            let opposite = TableDie8Geometry.face(number: 9 - face.number)
            #expect(opposite.map { simd_distance($0.normal, -face.normal) < 0.000_1 } == true)
        }
    }

    @Test("A face's corners wind counter-clockwise seen from outside, and lie in its plane")
    func cornersWindOutward() {
        let r = TableDie8Geometry.circumradius
        for face in TableDie8Geometry.faces {
            let corners = face.corners(circumradius: r)
            let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
            #expect(simd_distance(normal, face.normal) < 0.000_1)
            // The face's plane is `displayHeight / 2` from the center.
            #expect(abs(simd_dot(corners[0], face.normal) - TableDie8Geometry.displayHeight / 2) < 0.000_1)
        }
    }

    @Test("The die rests on a face as authored: face 1 up, so the bounds are as tall as the die stands")
    func authoredRestingOnAFace() {
        let corners = TableDie8Geometry.faces.flatMap { $0.corners(circumradius: TableDie8Geometry.circumradius) }
        let ys = corners.map(\.y)
        #expect(simd_distance(TableDie8Geometry.faces[0].normal, [0, 1, 0]) < 0.000_1)
        #expect(abs((ys.max() ?? 0) - TableDie8Geometry.displayHeight / 2) < 0.000_01)
        #expect(abs((ys.min() ?? 0) + TableDie8Geometry.displayHeight / 2) < 0.000_01)
    }

    @Test("Every face has its own atlas cell, and its triangle stays inside it")
    func atlasCellsAreDisjoint() {
        for face in TableDie8Geometry.faces {
            let cell = SIMD2<Float>(Float((face.number - 1) % 4), Float((face.number - 1) / 4))
            let lower = cell / SIMD2<Float>(4, 2)
            let upper = (cell + 1) / SIMD2<Float>(4, 2)
            for point in TableDie8Geometry.atlasCoordinates(for: face) {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
        }
    }
}
#endif
