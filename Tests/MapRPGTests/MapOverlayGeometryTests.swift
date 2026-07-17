// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

@Suite("Map editor adaptive overlay geometry")
struct MapOverlayGeometryTests {
    @Test(
        "Fan buttons keep their physical size and minimum center spacing",
        arguments: [1, 2, 3, 4, 5, 6]
    )
    func fanSpacing(itemCount: Int) {
        // Given
        let viewport = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let anchor = CGPoint(x: viewport.midX, y: viewport.midY)

        // When
        let placement = MapAdaptiveFanGeometry.placement(
            anchor: anchor,
            itemCount: itemCount,
            viewport: viewport
        )

        // Then
        #expect(placement.isValid)
        #expect(placement.buttonSize == CGSize(width: 48, height: 48))
        #expect(placement.minimumCenterSpacing == 60)
        #expect(placement.centers.count == itemCount)
        for firstIndex in placement.centers.indices {
            for secondIndex in placement.centers.indices where secondIndex > firstIndex {
                let distance = placement.centers[firstIndex]
                    .distance(to: placement.centers[secondIndex])
                #expect(distance + 0.001 >= placement.minimumCenterSpacing)
            }
        }
    }

    @Test("Fan chooses the quadrant pointing away from each viewport corner", arguments: FanEdge.allCases)
    func fanFlipsAwayFromEdges(edge: FanEdge) {
        // Given
        let viewport = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        // When
        let placement = MapAdaptiveFanGeometry.placement(
            anchor: edge.anchor,
            itemCount: 5,
            viewport: viewport
        )

        // Then
        #expect(placement.quadrant == edge.expectedQuadrant)
        #expect(placement.isFullyVisible)
        let safeFrame = viewport.insetBy(dx: 12, dy: 12)
        for frame in placement.buttonFrames {
            #expect(safeFrame.contains(frame))
        }
    }

    @Test("Fan uses its requested quadrant when every quadrant has equal space")
    func fanHonorsPreferredQuadrant() {
        // Given
        let viewport = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let anchor = CGPoint(x: 500, y: 400)

        // When
        let placement = MapAdaptiveFanGeometry.placement(
            anchor: anchor,
            itemCount: 5,
            viewport: viewport,
            preferredQuadrant: .bottomLeading
        )

        // Then
        #expect(placement.quadrant == .bottomLeading)
        #expect(placement.isFullyVisible)
    }

    @Test("Fan applies one group translation so clamping never changes spacing")
    func fanClampingPreservesSpacing() {
        // Given
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)

        // When
        let placement = MapAdaptiveFanGeometry.placement(
            anchor: CGPoint(x: 50, y: 50),
            itemCount: 5,
            viewport: viewport
        )

        // Then
        #expect(placement.isValid)
        #expect(!placement.isFullyVisible)
        for firstIndex in placement.centers.indices {
            for secondIndex in placement.centers.indices where secondIndex > firstIndex {
                let distance = placement.centers[firstIndex]
                    .distance(to: placement.centers[secondIndex])
                #expect(distance + 0.001 >= 60)
            }
        }
    }

    @Test("Fan exposes centers and offsets for viewport position or offset integration")
    func fanPositionAccessors() throws {
        // Given
        let anchor = CGPoint(x: 300, y: 300)
        let placement = MapAdaptiveFanGeometry.placement(
            anchor: anchor,
            itemCount: 3,
            viewport: CGRect(x: 0, y: 0, width: 900, height: 700)
        )

        // When
        let center = try #require(placement.center(at: 1))
        let offset = try #require(placement.offset(at: 1))

        // Then
        #expect(center == CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height))
        #expect(placement.center(at: 3) == nil)
        #expect(placement.offset(at: -1) == nil)
    }

    @Test("Fan rejects invalid viewport, anchor, and item count")
    func fanInvalidGeometry() {
        // Given / When
        let noItems = MapAdaptiveFanGeometry.placement(
            anchor: .zero,
            itemCount: 0,
            viewport: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let noViewport = MapAdaptiveFanGeometry.placement(
            anchor: .zero,
            itemCount: 2,
            viewport: .zero
        )
        let tooSmallForButtonInsets = MapAdaptiveFanGeometry.placement(
            anchor: CGPoint(x: 25, y: 25),
            itemCount: 2,
            viewport: CGRect(x: 0, y: 0, width: 50, height: 50)
        )
        let invalidAnchor = MapAdaptiveFanGeometry.placement(
            anchor: CGPoint(x: CGFloat.nan, y: 40),
            itemCount: 2,
            viewport: CGRect(x: 0, y: 0, width: 300, height: 300)
        )

        // Then
        #expect(!noItems.isValid && noItems.centers.isEmpty)
        #expect(!noViewport.isValid && noViewport.centers.isEmpty)
        #expect(!tooSmallForButtonInsets.isValid && tooSmallForButtonInsets.centers.isEmpty)
        #expect(!invalidAnchor.isValid && invalidAnchor.centers.isEmpty)
    }

    @Test("Touch loupe prefers upper-leading and leaves the requested gap")
    func touchLoupePreferredPlacement() {
        // Given
        let head = CGPoint(x: 250, y: 250)

        // When
        let placement = MapLoupeGeometry.placement(
            needleHead: head,
            viewport: CGRect(x: 0, y: 0, width: 500, height: 500),
            interaction: .touch
        )

        // Then
        #expect(placement.corner == .upperLeading)
        #expect(head.x - placement.frame.maxX == 24)
        #expect(head.y - placement.frame.maxY == 24)
        #expect(placement.frame.size == CGSize(width: 160, height: 160))
        #expect(placement.isFullyVisible)
        #expect(!placement.wasClamped)
    }

    @Test("Loupe sampling stays centered on the needle tip at three times viewport scale")
    func loupeSamplingUsesTipCoordinate() {
        let sampling = MapLoupeGeometry.sampling(
            sampleCoordinate: CGPoint(x: 40, y: 60),
            viewportScale: 0.5
        )

        #expect(sampling.scale == 1.5)
        #expect(sampling.offset == CGPoint(x: 20, y: -10))
    }

    @Test("Touch loupe falls back to lower-trailing near the upper-leading edge")
    func touchLoupeFallback() {
        // Given / When
        let placement = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 40, y: 40),
            viewport: CGRect(x: 0, y: 0, width: 500, height: 500),
            interaction: .touch
        )

        // Then
        #expect(placement.corner == .lowerTrailing)
        #expect(placement.isFullyVisible)
        #expect(!placement.wasClamped)
    }

    @Test("Pointer loupe prefers upper-trailing")
    func pointerLoupePreferredPlacement() {
        // Given / When
        let placement = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 250, y: 250),
            viewport: CGRect(x: 0, y: 0, width: 500, height: 500),
            interaction: .pointerOrSpatial
        )

        // Then
        #expect(placement.corner == .upperTrailing)
        #expect(placement.isFullyVisible)
        #expect(!placement.wasClamped)
    }

    @Test("Pointer loupe flips both axes near the upper-trailing edge")
    func pointerLoupeFlipsAtEdges() {
        // Given / When
        let placement = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 460, y: 40),
            viewport: CGRect(x: 0, y: 0, width: 500, height: 500),
            interaction: .pointerOrSpatial
        )

        // Then
        #expect(placement.corner == .lowerLeading)
        #expect(placement.isFullyVisible)
        #expect(!placement.wasClamped)
    }

    @Test("Loupe clamps into a non-zero-origin effective viewport after fallbacks")
    func loupeClampsInsideEffectiveViewport() {
        // Given
        let viewport = CGRect(x: 100, y: 50, width: 300, height: 260)

        // When
        let placement = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 250, y: 180),
            viewport: viewport,
            interaction: .touch
        )

        // Then
        #expect(placement.wasClamped)
        #expect(placement.isFullyVisible)
        #expect(viewport.insetBy(dx: 12, dy: 12).contains(placement.frame))
    }

    @Test("Loupe reports when an undersized viewport cannot contain 160 points")
    func loupeReportsUndersizedViewport() {
        // Given / When
        let placement = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 75, y: 75),
            viewport: CGRect(x: 0, y: 0, width: 150, height: 150),
            interaction: .touch
        )

        // Then
        #expect(placement.isValid)
        #expect(!placement.isFullyVisible)
        #expect(placement.wasClamped)
        #expect(placement.center == CGPoint(x: 75, y: 75))
    }

    @Test("Loupe rejects invalid viewport and needle head geometry")
    func loupeInvalidGeometry() {
        // Given / When
        let noViewport = MapLoupeGeometry.placement(
            needleHead: .zero,
            viewport: .zero,
            interaction: .touch
        )
        let invalidHead = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 40, y: CGFloat.infinity),
            viewport: CGRect(x: 0, y: 0, width: 300, height: 300),
            interaction: .pointerOrSpatial
        )
        let tooSmallForInsets = MapLoupeGeometry.placement(
            needleHead: CGPoint(x: 10, y: 10),
            viewport: CGRect(x: 0, y: 0, width: 20, height: 20),
            interaction: .touch
        )

        // Then
        #expect(!noViewport.isValid)
        #expect(noViewport.frame == .zero)
        #expect(!invalidHead.isValid)
        #expect(invalidHead.corner == nil)
        #expect(!tooSmallForInsets.isValid)
    }
}

enum FanEdge: CaseIterable, Sendable, CustomTestStringConvertible {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var anchor: CGPoint {
        switch self {
        case .topLeading: CGPoint(x: 40, y: 40)
        case .topTrailing: CGPoint(x: 960, y: 40)
        case .bottomLeading: CGPoint(x: 40, y: 760)
        case .bottomTrailing: CGPoint(x: 960, y: 760)
        }
    }

    var expectedQuadrant: MapOverlayQuadrant {
        switch self {
        case .topLeading: .bottomTrailing
        case .topTrailing: .bottomLeading
        case .bottomLeading: .topTrailing
        case .bottomTrailing: .topLeading
        }
    }

    var testDescription: String {
        switch self {
        case .topLeading: "top-leading edge"
        case .topTrailing: "top-trailing edge"
        case .bottomLeading: "bottom-leading edge"
        case .bottomTrailing: "bottom-trailing edge"
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
#endif
