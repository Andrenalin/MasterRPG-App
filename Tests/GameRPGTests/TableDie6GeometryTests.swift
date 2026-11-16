// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Geometry of the generated d6")
struct TableDie6GeometryTests {
    @Test("There is one face for each number from 1 to 6")
    func sixNumberedFaces() {
        #expect(TableDie6Geometry.faces.map(\.number) == Array(1 ... 6))
        #expect(TableDie6Geometry.face(number: 7) == nil)
    }

    @Test("Opposite faces add up to seven")
    func oppositeFacesAddUpToSeven() {
        for face in TableDie6Geometry.faces {
            let opposite = TableDie6Geometry.face(number: 7 - face.number)
            #expect(opposite?.normal == -face.normal)
        }
    }

    @Test("Every face is a square of the display height, wound counter-clockwise seen from outside, half of it from the center")
    func facesAreSquares() {
        let edge = TableDie6Geometry.displayHeight
        for face in TableDie6Geometry.faces {
            #expect(face.corners.count == 4)
            for i in 0 ..< 4 {
                #expect(abs(simd_distance(face.corners[i], face.corners[(i + 1) % 4]) - edge) < 0.000_01)
                #expect(abs(simd_dot(face.corners[i], face.normal) - edge / 2) < 0.000_01)
                let a = face.corners[i]
                let b = face.corners[(i + 1) % 4]
                let c = face.corners[(i + 2) % 4]
                #expect(simd_dot(simd_cross(b - a, c - b), face.normal) > 0)
            }
            #expect(abs(simd_dot(face.up, face.normal)) < 0.000_01)
        }
    }

    @Test("The six faces together make a closed cube: every corner is shared by three faces and the bounds are centered")
    func closedCube() {
        let corners = TableDie6Geometry.faces.flatMap(\.corners)
        #expect(corners.count == 24)
        for corner in corners {
            #expect(corners.filter { simd_distance($0, corner) < 0.000_01 }.count == 3)
            for axis in 0 ..< 3 {
                #expect(abs(abs(corner[axis]) - TableDie6Geometry.displayHeight / 2) < 0.000_01)
            }
        }
    }

    @Test("Each face has the number of pips its number says, inside the face")
    func pips() {
        for number in 1 ... 6 {
            let offsets = TableDie6Geometry.pipOffsets(for: number)
            #expect(offsets.count == number)
            #expect(Set(offsets.map { [$0.x, $0.y] }).count == number)
            for offset in offsets {
                #expect(abs(offset.x) + TableDie6Geometry.pipRadius < 0.5)
                #expect(abs(offset.y) + TableDie6Geometry.pipRadius < 0.5)
            }
        }
        #expect(TableDie6Geometry.pipOffsets(for: 7).isEmpty)
    }

    @Test("Every face keeps inside its own atlas cell, upright, with the face's center in the middle of the cell")
    func atlasSquares() {
        for face in TableDie6Geometry.faces {
            let index = face.number - 1
            let cell = SIMD2<Float>(Float(index % 3), Float(index / 3))
            let lower = SIMD2<Float>(cell.x / 3, cell.y / 2)
            let upper = SIMD2<Float>((cell.x + 1) / 3, (cell.y + 1) / 2)
            let square = TableDie6Geometry.atlasSquare(for: face)
            #expect(square.coordinates.count == 4)
            for point in square.coordinates {
                #expect(point.x >= lower.x && point.x <= upper.x)
                #expect(point.y >= lower.y && point.y <= upper.y)
            }
            #expect(simd_distance(square.center, (lower + upper) / 2) < 0.000_1)
            // Upright on the image: the first corner is the top left, the second the bottom left.
            #expect(square.coordinates[0].x < square.center.x && square.coordinates[0].y < square.center.y)
            #expect(square.coordinates[1].x < square.center.x && square.coordinates[1].y > square.center.y)
            // A face is as wide in the atlas as `faceWidthInAtlas` says.
            #expect(abs((square.coordinates[3].x - square.coordinates[0].x) - TableDie6Geometry.faceWidthInAtlas) < 0.000_1)
        }
    }
}
#endif
