// @copyright André Trettin

import CoreGraphics
import Foundation

/// Turns the freehand line an Apple Pencil draws around a room into the room's polygon.
///
/// Pure geometry, no SwiftUI: the stroke is sampled in map (content) coordinates, simplified
/// with Ramer–Douglas–Peucker and implicitly closed, because a room polygon always closes from
/// its last point back to its first one.
struct MapPencilStroke: Equatable {
    /// Screen distance, in points, a stroke may deviate from the polygon edges.
    static let screenTolerance: CGFloat = 6
    /// A stroke whose polygon spans less than this on screen is a scribble or a tap, not a room.
    static let minimumScreenExtent: CGFloat = 24
    /// Samples closer than this on screen are dropped while drawing.
    static let sampleScreenDistance: CGFloat = 2

    private(set) var points: [CGPoint] = []

    /// Adds a sample unless it is closer than `minimumDistance` to the previous one.
    /// Returns whether the sample was kept.
    @discardableResult
    mutating func append(_ point: CGPoint, minimumDistance: CGFloat = 0) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        if let last = points.last, last.distance(to: point) < minimumDistance {
            return false
        }
        points.append(point)
        return true
    }

    mutating func removeAll() {
        points.removeAll(keepingCapacity: true)
    }

    var isEmpty: Bool { points.isEmpty }

    /// The room polygon for this stroke, or `nil` if the stroke is too small to be a room.
    /// - Parameter scale: the viewport scale, so the tolerances stay constant on screen.
    func polygon(scale: CGFloat) -> [CGPoint]? {
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let simplified = Self.simplifiedClosed(
            points,
            tolerance: Self.screenTolerance / safeScale
        )
        guard simplified.count >= 3,
              let bounds = simplified.bounds,
              max(bounds.width, bounds.height) >= Self.minimumScreenExtent / safeScale else {
            return nil
        }
        return simplified
    }

    /// Simplifies a stroke that is meant to be a closed loop. The loop is split at the sample
    /// farthest from its start, because the start and the end of a closed loop lie close
    /// together, which gives Ramer–Douglas–Peucker no usable baseline for the whole line.
    static func simplifiedClosed(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 3, let start = points.first else { return points }
        var farthestIndex = 0
        var farthestDistance: CGFloat = 0
        for (index, point) in points.enumerated() {
            let distance = start.distance(to: point)
            if distance > farthestDistance {
                farthestDistance = distance
                farthestIndex = index
            }
        }
        guard farthestIndex > 0 else { return [start] }

        let firstHalf = simplified(Array(points[0...farthestIndex]), tolerance: tolerance)
        let secondHalf = simplified(Array(points[farthestIndex...]), tolerance: tolerance)
        // The far point ends the first half and starts the second; the start point (end of the
        // second half) is the polygon's first point again and is not repeated.
        var polygon = firstHalf + secondHalf.dropFirst()
        if polygon.count > 1,
           let first = polygon.first,
           let last = polygon.last,
           first.distance(to: last) <= tolerance {
            polygon.removeLast()
        }
        return polygon
    }

    /// Ramer–Douglas–Peucker simplification of an open polyline. Iterative, so a long stroke
    /// cannot overflow the stack.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var ranges = [(0, points.count - 1)]
        while let (lower, upper) = ranges.popLast() {
            guard upper - lower > 1 else { continue }
            var farthestIndex = lower
            var farthestDistance: CGFloat = 0
            for index in (lower + 1)..<upper {
                let distance = points[index].distance(
                    toSegmentFrom: points[lower],
                    to: points[upper]
                )
                if distance > farthestDistance {
                    farthestDistance = distance
                    farthestIndex = index
                }
            }
            if farthestDistance > tolerance {
                keep[farthestIndex] = true
                ranges.append((lower, farthestIndex))
                ranges.append((farthestIndex, upper))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: start) }
        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
        return distance(to: CGPoint(x: start.x + t * dx, y: start.y + t * dy))
    }
}
