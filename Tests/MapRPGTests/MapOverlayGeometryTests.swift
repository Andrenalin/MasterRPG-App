// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

@Suite("Map editor overlay geometry")
struct MapOverlayGeometryTests {
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
#endif
