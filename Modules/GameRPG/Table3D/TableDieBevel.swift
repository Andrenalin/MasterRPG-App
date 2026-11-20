// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import simd

// The dice on the 3D table are convex polyhedra whose faces each have their own vertices (flat
// shading). A sharp edge looks like a polygon, so every die gets a small bezel: each face is pulled
// in by `width` along its plane, a flat strip joins the pulled-in edges of two neighbouring faces,
// and a small patch closes each corner. The face planes stay where they were, so the height the
// die rests at and the pose of a rolled value do not change. Pure, so it is unit-tested on iOS.

enum TableDieBevel {
    /// How far a face is pulled in from its edges, in meters. About 4 % of the die's height.
    static let width: Float = 0.0012

    /// A face of the die before it is beveled.
    struct Face {
        /// The corners, counter-clockwise seen from outside.
        let corners: [SIMD3<Float>]
        let normal: SIMD3<Float>
        /// The atlas coordinates (0…1, y down) of `corners`, which place the numerals.
        let atlas: [SIMD2<Float>]
    }

    /// The beveled mesh. `coordinates` are texture coordinates (v up), ready for `MeshDescriptor`.
    struct Mesh {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        /// Adds a convex polygon as a triangle fan.
        mutating func add(polygon: [SIMD3<Float>], normal: SIMD3<Float>, coordinates uvs: [SIMD2<Float>]) {
            guard polygon.count >= 3 else { return }
            let base = UInt32(positions.count)
            positions += polygon
            normals += Array(repeating: normal, count: polygon.count)
            coordinates += uvs
            for corner in 1 ..< UInt32(polygon.count - 1) {
                indices += [base, base + corner, base + corner + 1]
            }
        }
    }

    static func mesh(faces: [Face], width: Float = TableDieBevel.width) -> Mesh {
        var mesh = Mesh()
        let insets = faces.map { inset(corners: $0.corners, normal: $0.normal, by: width) }

        // The faces, pulled in. They keep the atlas mapping, so numerals do not move.
        for (face, inset) in zip(faces, insets) {
            let uvs = inset.map { atlasCoordinate(of: $0, in: face) }
            mesh.add(polygon: inset, normal: face.normal, coordinates: uvs.map(textureCoordinate))
        }

        // Which vertex of the die each corner of each face is.
        var vertices: [SIMD3<Float>] = []
        let vertexIds: [[Int]] = faces.map { face in
            face.corners.map { corner in
                if let found = vertices.firstIndex(where: { simd_distance($0, corner) < 0.000_01 }) {
                    return found
                }
                vertices.append(corner)
                return vertices.count - 1
            }
        }

        // A strip along every edge that two faces share.
        var owners: [Edge: (face: Int, corner: Int)] = [:]
        for (faceIndex, ids) in vertexIds.enumerated() {
            for corner in ids.indices {
                owners[Edge(from: ids[corner], to: ids[(corner + 1) % ids.count])] = (faceIndex, corner)
            }
        }
        for (edge, a) in owners where edge.from < edge.to {
            guard let b = owners[Edge(from: edge.to, to: edge.from)] else { continue }
            let nextA = (a.corner + 1) % faces[a.face].corners.count
            let nextB = (b.corner + 1) % faces[b.face].corners.count
            // Face A runs P → Q, face B Q → P; this winding seen from outside has the strip's
            // interior on the left of every side.
            let polygon = [insets[b.face][nextB], insets[b.face][b.corner], insets[a.face][nextA], insets[a.face][a.corner]]
            let normal = simd_normalize(faces[a.face].normal + faces[b.face].normal)
            // The strip is body color: all its corners sample the same spot of the cell margin.
            let uv = textureCoordinate(atlasCoordinate(of: polygon[3], in: faces[a.face]))
            mesh.add(polygon: polygon, normal: normal, coordinates: Array(repeating: uv, count: 4))
        }

        // A patch at every corner of the die.
        for vertex in vertices.indices {
            var points: [SIMD3<Float>] = []
            var normal = SIMD3<Float>.zero
            var reference: (face: Int, point: SIMD3<Float>)?
            for (faceIndex, ids) in vertexIds.enumerated() {
                guard let corner = ids.firstIndex(of: vertex) else { continue }
                points.append(insets[faceIndex][corner])
                normal += faces[faceIndex].normal
                reference = reference ?? (faceIndex, insets[faceIndex][corner])
            }
            guard points.count >= 3, let reference, simd_length(normal) > 0.000_001 else { continue }
            normal = simd_normalize(normal)
            let center = points.reduce(.zero, +) / Float(points.count)
            let first = simd_normalize(points[0] - center)
            let second = simd_cross(normal, first)
            // Ascending angle about the outward normal is counter-clockwise seen from outside.
            points.sort { angle($0 - center, first, second) < angle($1 - center, first, second) }
            let uv = textureCoordinate(atlasCoordinate(of: reference.point, in: faces[reference.face]))
            mesh.add(polygon: points, normal: normal, coordinates: Array(repeating: uv, count: points.count))
        }
        return mesh
    }

    // MARK: Helpers

    private struct Edge: Hashable {
        let from: Int
        let to: Int
    }

    private static func angle(_ vector: SIMD3<Float>, _ first: SIMD3<Float>, _ second: SIMD3<Float>) -> Float {
        atan2(simd_dot(vector, second), simd_dot(vector, first))
    }

    /// The atlas image has y down, texture coordinates have v up.
    private static func textureCoordinate(_ atlas: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(atlas.x, 1 - atlas.y)
    }

    /// The polygon with every edge moved inwards by `distance`, within the plane of the face.
    static func inset(corners: [SIMD3<Float>], normal: SIMD3<Float>, by distance: Float) -> [SIMD3<Float>] {
        let count = corners.count
        // Inwards, in the plane, is to the left of an edge of a polygon counter-clockwise seen from outside.
        let inwards: [SIMD3<Float>] = corners.indices.map { index in
            let direction = simd_normalize(corners[(index + 1) % count] - corners[index])
            return simd_cross(normal, direction)
        }
        return corners.indices.map { index in
            let before = inwards[(index + count - 1) % count]
            let after = inwards[index]
            // The miter: the corner where the two moved edges meet.
            return corners[index] + (before + after) * (distance / (1 + simd_dot(before, after)))
        }
    }

    /// The atlas coordinate of a point of the face's plane, from the mapping the face's corners define.
    static func atlasCoordinate(of point: SIMD3<Float>, in face: Face) -> SIMD2<Float> {
        let e1 = face.corners[1] - face.corners[0]
        let e2 = face.corners[2] - face.corners[0]
        let d = point - face.corners[0]
        let g11 = simd_dot(e1, e1)
        let g12 = simd_dot(e1, e2)
        let g22 = simd_dot(e2, e2)
        let determinant = g11 * g22 - g12 * g12
        guard abs(determinant) > 0 else { return face.atlas[0] }
        let b1 = simd_dot(d, e1)
        let b2 = simd_dot(d, e2)
        let s = (b1 * g22 - b2 * g12) / determinant
        let t = (b2 * g11 - b1 * g12) / determinant
        return face.atlas[0] + (face.atlas[1] - face.atlas[0]) * s + (face.atlas[2] - face.atlas[0]) * t
    }
}
#endif
