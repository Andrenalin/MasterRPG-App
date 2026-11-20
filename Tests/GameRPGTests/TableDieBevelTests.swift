// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Bevel of the generated dice")
struct TableDieBevelTests {
    private static func faces(of kind: String) -> [TableDieBevel.Face] {
        switch kind {
            case "d4":
                TableDie4Geometry.faces.map {
                    .init(corners: $0.corners, normal: $0.normal, atlas: TableDie4Geometry.atlasFace(for: $0).coordinates)
                }
            case "d6":
                TableDie6Geometry.faces.map {
                    .init(corners: $0.corners, normal: $0.normal, atlas: TableDie6Geometry.atlasSquare(for: $0).coordinates)
                }
            case "d8":
                TableDie8Geometry.faces.map {
                    .init(
                        corners: $0.corners(circumradius: TableDie8Geometry.circumradius),
                        normal: $0.normal,
                        atlas: TableDie8Geometry.atlasCoordinates(for: $0)
                    )
                }
            case "d10":
                TableDie10Geometry.faces.map {
                    .init(corners: $0.corners, normal: $0.normal, atlas: TableDie10Geometry.atlasKite(for: $0).coordinates)
                }
            case "d12":
                TableDie12Geometry.faces.map {
                    .init(corners: $0.corners, normal: $0.normal, atlas: TableDie12Geometry.atlasPentagon(for: $0).coordinates)
                }
            default:
                TableDie20Geometry.faces.map {
                    .init(corners: $0.corners, normal: $0.normal, atlas: TableDie20Geometry.atlasTriangle(for: $0).coordinates)
                }
        }
    }

    @Test("The inset of a square moves every edge inwards by the width")
    func insetOfSquare() {
        let corners: [SIMD3<Float>] = [[-1, 0, 1], [1, 0, 1], [1, 0, -1], [-1, 0, -1]]
        // Seen from above (+y is the outside) this winds counter-clockwise.
        let inset = TableDieBevel.inset(corners: corners, normal: [0, 1, 0], by: 0.1)
        for (original, moved) in zip(corners, inset) {
            #expect(abs(abs(moved.x) - 0.9) < 0.000_01)
            #expect(abs(abs(moved.z) - 0.9) < 0.000_01)
            #expect(simd_dot(original, moved) > 0)
        }
    }

    @Test("Every die gets a bevel that is watertight: each edge of the mesh is used by two triangles of opposite direction", arguments: ["d4", "d6", "d8", "d10", "d12", "d20"])
    func meshIsClosed(kind: String) {
        let mesh = TableDieBevel.mesh(faces: Self.faces(of: kind))
        #expect(!mesh.indices.isEmpty)
        #expect(mesh.positions.count == mesh.normals.count)
        #expect(mesh.positions.count == mesh.coordinates.count)

        // Positions are duplicated per face, so merge them to find shared edges.
        var merged: [SIMD3<Float>] = []
        func id(_ point: SIMD3<Float>) -> Int {
            if let found = merged.firstIndex(where: { simd_distance($0, point) < 0.000_01 }) { return found }
            merged.append(point)
            return merged.count - 1
        }
        struct Edge: Hashable { let from: Int; let to: Int }
        var count: [Edge: Int] = [:]
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ids = (0 ..< 3).map { id(mesh.positions[Int(mesh.indices[triangle + $0])]) }
            for i in 0 ..< 3 {
                count[Edge(from: ids[i], to: ids[(i + 1) % 3]), default: 0] += 1
            }
        }
        for (edge, uses) in count {
            #expect(uses == 1)
            #expect(count[Edge(from: edge.to, to: edge.from)] == 1)
        }
    }

    @Test("The triangles wind counter-clockwise seen from outside, like their normals", arguments: ["d4", "d6", "d8", "d10", "d12", "d20"])
    func windingMatchesNormals(kind: String) {
        let mesh = TableDieBevel.mesh(faces: Self.faces(of: kind))
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let index = (0 ..< 3).map { Int(mesh.indices[triangle + $0]) }
            let a = mesh.positions[index[0]]
            let b = mesh.positions[index[1]]
            let c = mesh.positions[index[2]]
            let winding = simd_cross(b - a, c - b)
            guard simd_length(winding) > 0 else { continue }
            #expect(simd_dot(winding, mesh.normals[index[0]]) > 0)
        }
    }

    @Test("The lowest point stays on the face plane, so the rest height does not change", arguments: ["d4", "d6", "d8", "d10", "d12", "d20"])
    func facePlanesStay(kind: String) {
        let faces = Self.faces(of: kind)
        let mesh = TableDieBevel.mesh(faces: faces)
        for face in faces {
            let plane = simd_dot(face.corners[0], face.normal)
            let deepest = mesh.positions.map { simd_dot($0, face.normal) }.max() ?? 0
            #expect(abs(deepest - plane) < 0.000_01)
        }
    }

    @Test("A beveled face keeps the atlas mapping of its numerals")
    func atlasMappingIsKept() {
        let face = Self.faces(of: "d6")[0]
        let center = face.corners.reduce(.zero, +) / Float(face.corners.count)
        let expected = face.atlas.reduce(.zero, +) / Float(face.atlas.count)
        let mapped = TableDieBevel.atlasCoordinate(of: center, in: face)
        #expect(simd_distance(mapped, expected) < 0.000_01)
    }
}
#endif
