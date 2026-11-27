// @copyright André Trettin

import CoreGraphics

/// Splits a room outline into triangles, so the 3D table's hit volume of an L- or U-shaped room
/// does not reach into its neighbours as a convex hull did. Pure, so it is tested on iOS.
/// See CODE_AUDIT_29 §5.25.
enum PolygonTriangulation {
    /// Whether the simple polygon turns the same way at every corner.
    static func isConvex(_ points: [CGPoint]) -> Bool {
        let polygon = cleaned(points)
        guard polygon.count > 3 else { return polygon.count == 3 }
        var sign: CGFloat = 0
        for index in polygon.indices {
            let turn = cross(polygon[index], polygon[(index + 1) % polygon.count], polygon[(index + 2) % polygon.count])
            guard turn != 0 else { continue }
            if sign == 0 {
                sign = turn
            } else if (turn > 0) != (sign > 0) {
                return false
            }
        }
        return true
    }

    /// The triangles of a simple polygon by ear clipping, as index triples into the cleaned
    /// points it returns with them. `nil` for fewer than three distinct points or an outline
    /// that crosses itself (no ear is left), so the caller can fall back to the hull.
    static func triangles(of points: [CGPoint]) -> (points: [CGPoint], triangles: [[Int]])? {
        let polygon = cleaned(points)
        guard polygon.count >= 3 else { return nil }
        // Counter-clockwise order, so an ear is a left turn.
        var remaining = Array(polygon.indices)
        if signedArea(polygon) < 0 { remaining.reverse() }
        var result: [[Int]] = []
        result.reserveCapacity(polygon.count - 2)
        var guardCount = 0
        while remaining.count > 3 {
            guardCount += 1
            guard guardCount <= polygon.count * polygon.count else { return nil }
            var clipped = false
            for position in remaining.indices {
                let previous = remaining[(position + remaining.count - 1) % remaining.count]
                let current = remaining[position]
                let next = remaining[(position + 1) % remaining.count]
                guard cross(polygon[previous], polygon[current], polygon[next]) > 0 else { continue }
                let containsOther = remaining.contains { index in
                    index != previous && index != current && index != next
                        && contains(polygon[index], in: (polygon[previous], polygon[current], polygon[next]))
                }
                guard !containsOther else { continue }
                result.append([previous, current, next])
                remaining.remove(at: position)
                clipped = true
                break
            }
            guard clipped else { return nil }
        }
        result.append(remaining)
        return (polygon, result)
    }

    /// Drops repeated points and a closing point equal to the first.
    private static func cleaned(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points where result.last != point {
            result.append(point)
        }
        if result.count > 1, result.first == result.last { result.removeLast() }
        return result
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var area: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    /// Inside or on the edge of the counter-clockwise triangle.
    private static func contains(_ point: CGPoint, in triangle: (CGPoint, CGPoint, CGPoint)) -> Bool {
        cross(triangle.0, triangle.1, point) >= 0
            && cross(triangle.1, triangle.2, point) >= 0
            && cross(triangle.2, triangle.0, point) >= 0
    }
}
