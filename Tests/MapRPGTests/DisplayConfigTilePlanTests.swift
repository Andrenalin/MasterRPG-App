// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_TestGaps §8.5: which part of the photo the cover-tile preview shows.
@Suite("Display config tile plan")
struct DisplayConfigTilePlanTests {
    @Test("Four corner points give the tile's bounding rectangle")
    func fourPointsGiveBounds() {
        let corners = [CGPoint(x: 10, y: 20), CGPoint(x: 60, y: 20), CGPoint(x: 60, y: 80), CGPoint(x: 10, y: 80)]

        #expect(DisplayConfigTilePlan.tileRect(coordinates: corners) == CGRect(x: 10, y: 20, width: 50, height: 60))
    }

    @Test("The corners may come in any order")
    func orderDoesNotMatter() {
        let shuffled = [CGPoint(x: 60, y: 80), CGPoint(x: 10, y: 20), CGPoint(x: 10, y: 80), CGPoint(x: 60, y: 20)]

        #expect(DisplayConfigTilePlan.tileRect(coordinates: shuffled) == CGRect(x: 10, y: 20, width: 50, height: 60))
    }

    @Test("Anything but four points is no tile", arguments: [0, 1, 2, 3, 5, 8])
    func otherCountsAreNoTile(count: Int) {
        let points = (0..<count).map { CGPoint(x: $0 * 10, y: $0 * 5) }

        #expect(DisplayConfigTilePlan.tileRect(coordinates: points) == nil)
    }
}
#endif
