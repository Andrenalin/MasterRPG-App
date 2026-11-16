// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d4")
struct TableDie4GeometryTests {
    @Test("Corner 1 points up, and the four corners are a regular tetrahedron around the origin")
    func regularTetrahedron() {
        let directions = TableDie4Geometry.cornerDirections
        #expect(directions.count == 4)
        #expect(simd_distance(directions[0], [0, 1, 0]) < 0.000_1)
        #expect(simd_length(directions.reduce(.zero, +)) < 0.000_1)
        for a in 0 ..< 4 {
            for b in (a + 1) ..< 4 {
                #expect(abs(simd_dot(directions[a], directions[b]) + 1.0 / 3.0) < 0.000_1)
            }
        }
        #expect(TableDie4Geometry.direction(ofNumber: 5) == nil)
    }

    @Test("The die rests on a face as authored: the bounds run from a quarter of its height below the origin to three quarters above")
    func authoredRestingOnAFace() {
        let ys = TableDie4Geometry.faces.flatMap(\.corners).map(\.y)
        let height = TableDie4Geometry.displayHeight
        #expect(abs((ys.max() ?? 0) - height * 3 / 4) < 0.000_01)
        #expect(abs((ys.min() ?? 0) + height / 4) < 0.000_01)
    }

    @Test("Every face is the distance of a quarter of the height from the center, whatever corner is up")
    func facesAreEquallyFarFromTheCenter() {
        for face in TableDie4Geometry.faces {
            for corner in face.corners {
                #expect(abs(simd_dot(corner, face.normal) - TableDie4Geometry.displayHeight / 4) < 0.000_01)
            }
        }
    }

    @Test("Each face lies opposite its corner, winds counter-clockwise seen from outside, and carries the numbers of its corners")
    func faces() {
        #expect(TableDie4Geometry.faces.map(\.opposite) == [1, 2, 3, 4])
        for face in TableDie4Geometry.faces {
            let opposite = TableDie4Geometry.direction(ofNumber: face.opposite)
            #expect(opposite.map { simd_distance($0, -face.normal) < 0.000_1 } == true)
            let turn = simd_cross(face.corners[1] - face.corners[0], face.corners[2] - face.corners[0])
            #expect(simd_dot(turn, face.normal) > 0)
            #expect(Set(face.numbers) == Set(1 ... 4).subtracting([face.opposite]))
            // Each number stands at its own corner on every face.
            for (corner, number) in zip(face.corners, face.numbers) {
                let direction = TableDie4Geometry.direction(ofNumber: number) ?? .zero
                #expect(simd_distance(simd_normalize(corner), direction) < 0.000_1)
            }
        }
    }

    @Test("Every face keeps inside its own atlas cell, each number inside the face and pointing at its corner")
    func atlasFaces() {
        for face in TableDie4Geometry.faces {
            let index = face.opposite - 1
            let cell = SIMD2<Float>(Float(index % 2), Float(index / 2))
            let lower = cell / 2
            let upper = (cell + 1) / 2
            let atlas = TableDie4Geometry.atlasFace(for: face)
            #expect(atlas.coordinates.count == 3)
            #expect(atlas.numerals.map(\.number) == face.numbers)
            for point in atlas.coordinates + atlas.numerals.map(\.center) {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
            // The numeral stands between the center of the face and its corner.
            let center = atlas.coordinates.reduce(.zero, +) / 3
            for (numeral, corner) in zip(atlas.numerals, atlas.coordinates) {
                #expect(simd_dot(numeral.center - center, corner - center) > 0)
                #expect(simd_distance(numeral.center - center, (corner - center) / 2) < 0.000_1)
                #expect(simd_dot(simd_normalize(numeral.direction), simd_normalize(corner - center)) > 0.999)
            }
        }
    }
}
#endif
