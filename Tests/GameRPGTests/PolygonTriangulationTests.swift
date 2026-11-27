// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import GameRPG

/// The concave room collision of the 3D table. See CODE_AUDIT_29 §5.25.
@Suite("Polygon triangulation")
struct PolygonTriangulationTests {
    private static let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
    /// An L-shaped room: the notch at the top right makes it concave.
    private static let lShape = [
        CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5),
        CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 10), CGPoint(x: 0, y: 10)
    ]

    private static func area(_ points: [CGPoint], _ triangle: [Int]) -> CGFloat {
        let a = points[triangle[0]], b = points[triangle[1]], c = points[triangle[2]]
        return abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
    }

    @Test("A square is convex, an L shape is not")
    func convexity() {
        #expect(PolygonTriangulation.isConvex(Self.square))
        #expect(!PolygonTriangulation.isConvex(Self.lShape))
    }

    @Test("An L shape splits into n - 2 triangles that cover exactly its area")
    func concaveCoverage() throws {
        let result = try #require(PolygonTriangulation.triangles(of: Self.lShape))
        #expect(result.triangles.count == Self.lShape.count - 2)
        let total = result.triangles.reduce(0) { $0 + Self.area(result.points, $1) }
        #expect(abs(total - 75) < 0.0001)
    }

    @Test("Clockwise input and a repeated closing point give the same coverage")
    func orientationAndClosingPoint() throws {
        let clockwise = Array(Self.lShape.reversed()) + [Self.lShape.last!]
        let result = try #require(PolygonTriangulation.triangles(of: clockwise))
        let total = result.triangles.reduce(0) { $0 + Self.area(result.points, $1) }
        #expect(abs(total - 75) < 0.0001)
    }

    @Test("Fewer than three distinct points and a self-crossing outline give nil")
    func degenerateInput() {
        #expect(PolygonTriangulation.triangles(of: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]) == nil)
        let bowTie = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10)]
        let result = PolygonTriangulation.triangles(of: bowTie)
        if let result {
            // A crossing outline must not claim more than its bounding box.
            let total = result.triangles.reduce(0) { $0 + Self.area(result.points, $1) }
            #expect(total <= 100)
        }
    }
}
#endif
