// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
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

    @Test("Two needle actions form one compact row above the needle")
    func compactNeedleFan() throws {
        let anchor = CGPoint(x: 500, y: 400)
        let placement = MapAdaptiveFanGeometry.verticalPlacement(
            anchor: anchor,
            itemCount: 2,
            viewport: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            preferredDirection: .top,
            centerSpacing: MapAdaptiveFanGeometry.buttonSize.width * 2
        )
        let first = try #require(placement.center(at: 0))
        let second = try #require(placement.center(at: 1))

        #expect(placement.isFullyVisible)
        #expect(first.y < anchor.y && second.y < anchor.y)
        #expect(abs(first.y - second.y) < 0.001)
        #expect(abs(first.distance(to: second) - 96) < 0.001)
        #expect(abs(placement.buttonFrames[1].minX - placement.buttonFrames[0].maxX - 48) < 0.001)
    }

    @Test("Needle actions flip below and stay inside a nonzero safe viewport")
    func needleFanRespectsSafeViewport() {
        let viewport = CGRect(x: 72, y: 54, width: 760, height: 560)
        let anchor = CGPoint(x: 90, y: 70)
        let placement = MapAdaptiveFanGeometry.verticalPlacement(
            anchor: anchor,
            itemCount: 2,
            viewport: viewport,
            preferredDirection: .top,
            centerSpacing: MapAdaptiveFanGeometry.buttonSize.width * 2
        )
        let safeFrame = viewport.insetBy(
            dx: MapAdaptiveFanGeometry.edgeInset,
            dy: MapAdaptiveFanGeometry.edgeInset
        )

        #expect(placement.centers.allSatisfy { $0.y > anchor.y })
        #expect(placement.buttonFrames.allSatisfy { safeFrame.contains($0) })
        #expect(placement.isFullyVisible)
    }

    @Test("Pin actions center below the pin and retain top-bottom edge flipping")
    func pinFanCentersBelowAndFlips() {
        let viewport = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let centerPlacement = MapAdaptiveFanGeometry.verticalPlacement(
            anchor: CGPoint(x: 500, y: 400),
            itemCount: 5,
            viewport: viewport,
            preferredDirection: .bottom
        )
        let bottomEdgePlacement = MapAdaptiveFanGeometry.verticalPlacement(
            anchor: CGPoint(x: 500, y: 770),
            itemCount: 5,
            viewport: viewport,
            preferredDirection: .bottom
        )

        #expect(centerPlacement.centers.allSatisfy { $0.y > 400 })
        #expect(bottomEdgePlacement.centers.allSatisfy { $0.y < 770 })
        #expect(centerPlacement.isFullyVisible)
        #expect(bottomEdgePlacement.isFullyVisible)
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
        let destination = sampling.destinationRectangle(
            canvasSize: CGSize(width: 1_200, height: 800)
        )
        let sampledPoint = CGPoint(
            x: destination.minX + 40 * sampling.scale,
            y: destination.minY + 60 * sampling.scale
        )

        #expect(sampling.scale == 1.5)
        #expect(sampling.offset == CGPoint(x: 20, y: -10))
        #expect(sampledPoint == CGPoint(x: 80, y: 80))
    }

    @Test(
        "Loupe centers the oriented needle-tip coordinate for every quarter turn",
        arguments: [0.0, 90.0, 180.0, 270.0]
    )
    func loupeSamplingCentersRotatedTip(degrees: Double) {
        let imageSize = CGSize(width: 400, height: 240)
        let canvasSize = ViewportGeometry.rotatedContentSize(
            imageSize,
            rotationDegrees: degrees
        )
        let tip = ViewportGeometry.rotatedPoint(
            fromContent: CGPoint(x: 75, y: 160),
            contentSize: imageSize,
            rotationDegrees: degrees
        )
        let sampling = MapLoupeGeometry.sampling(
            sampleCoordinate: tip,
            viewportScale: 0.75
        )
        let destination = sampling.destinationRectangle(canvasSize: canvasSize)
        let sampledPoint = CGPoint(
            x: destination.minX + tip.x * sampling.scale,
            y: destination.minY + tip.y * sampling.scale
        )

        #expect(abs(sampledPoint.x - MapLoupeGeometry.size.width / 2) < 0.001)
        #expect(abs(sampledPoint.y - MapLoupeGeometry.size.height / 2) < 0.001)
    }

    @Test("Needle drag converts viewport locations into one logical tip coordinate")
    func needleDragCoordinateConversion() {
        let configuration = ViewportConfiguration(
            id: UUID(),
            contentSize: CGSize(width: 1_200, height: 800),
            containerSize: CGSize(width: 600, height: 400),
            panPolicy: .minimumVisible(44)
        )
        let geometry = ViewportGeometry(configuration: configuration)
        let transform = ViewportTransform(
            scale: 1.5,
            offset: CGPoint(x: -130, y: 25)
        )

        let coordinate = MapNeedleDragGeometry.coordinate(
            originalCoordinate: CGPoint(x: 300, y: 240),
            startViewportPoint: CGPoint(x: 170, y: 145),
            currentViewportPoint: CGPoint(x: 260, y: 205),
            viewportGeometry: geometry,
            transform: transform
        )

        #expect(abs(coordinate.x - 360) < 0.001)
        #expect(abs(coordinate.y - 280) < 0.001)
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
