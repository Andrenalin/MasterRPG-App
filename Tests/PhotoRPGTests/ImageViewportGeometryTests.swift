// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

@Suite("Image viewport geometry")
struct ImageViewportGeometryTests {
    @Test("Rotated bounds support cardinal and arbitrary angles", arguments: RotationTestCase.cases)
    func rotatedBounds(testCase: RotationTestCase) {
        // Given
        let configuration = configuration(imageSize: CGSize(width: 100, height: 50), degrees: testCase.degrees)

        // When
        let geometry = ImageViewportGeometry(configuration: configuration)

        // Then
        expectApproximately(geometry.normalizedDegrees, testCase.normalizedDegrees)
        expectApproximately(geometry.rotatedImageSize, testCase.expectedSize)
    }

    @Test(
        "Non-finite rotations normalize to zero",
        arguments: [Double.nan, Double.infinity, -Double.infinity]
    )
    func nonFiniteRotation(degrees: Double) {
        // Given / When
        let geometry = ImageViewportGeometry(configuration: configuration(degrees: degrees))

        // Then
        #expect(geometry.normalizedDegrees == 0)
        expectApproximately(geometry.rotatedImageSize, CGSize(width: 100, height: 50))
    }

    @Test("Invalid dimensions produce finite safe viewports", arguments: InvalidSizeTestCase.cases)
    func invalidDimensions(testCase: InvalidSizeTestCase) {
        // Given
        let configuration = ImageViewportConfiguration(
            id: UUID(),
            imageSize: testCase.imageSize,
            containerSize: testCase.containerSize,
            degrees: 45
        )

        // When
        let geometry = ImageViewportGeometry(configuration: configuration)
        let fitViewport = geometry.fitViewport
        let zoomedViewport = geometry.zoomedViewport(
            from: ImageViewport(
                scale: CGFloat.nan,
                offset: CGPoint(x: CGFloat.infinity, y: CGFloat.nan)
            ),
            toScale: CGFloat.infinity,
            anchor: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)
        )

        // Then
        #expect(geometry.fitScale.isFinite)
        #expect(geometry.maximumScale.isFinite)
        #expect(geometry.fillScale.isFinite)
        #expect(fitViewport.isFinite)
        #expect(zoomedViewport.isFinite)
    }

    @Test("Minimum zoom remains relative to fit when fit is below point one")
    func relativeMinimumScale() {
        // Given
        let geometry = ImageViewportGeometry(configuration: configuration(
            imageSize: CGSize(width: 5_000, height: 5_000),
            containerSize: CGSize(width: 100, height: 100)
        ))

        // When
        let clampedScale = geometry.clampedScale(0.001)

        // Then
        expectApproximately(geometry.fitScale, 0.02)
        expectApproximately(clampedScale, geometry.fitScale)
        expectApproximately(geometry.maximumScale, 1)
    }

    @Test("Double tap clamps a letterbox tap to the visible image and toggles back to fit")
    func letterboxDoubleTap() {
        // Given
        let geometry = ImageViewportGeometry(configuration: configuration(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        ))
        let fitViewport = geometry.fitViewport

        // When
        let fromLetterbox = geometry.doubleTapViewport(from: fitViewport, at: CGPoint(x: 50, y: 0))
        let fromImageEdge = geometry.doubleTapViewport(from: fitViewport, at: CGPoint(x: 50, y: 25))
        let resetViewport = geometry.doubleTapViewport(from: fromLetterbox, at: CGPoint(x: 50, y: 50))

        // Then
        expectApproximately(fitViewport.scale, 0.5)
        expectApproximately(fitViewport.offset, CGPoint(x: 0, y: 25))
        expectApproximately(fromLetterbox.scale, 2)
        expectApproximately(fromLetterbox.offset, fromImageEdge.offset)
        expectOffsetWithinBounds(fromLetterbox.offset, scale: fromLetterbox.scale, geometry: geometry)
        expectApproximately(resetViewport, fitViewport)
    }

    @Test("Configuration changes are detected even when the photo identifier is unchanged")
    func configurationEqualityIncludesViewportInputs() {
        // Given
        let id = UUID()
        let original = configuration(id: id)

        // When
        let resizedContainer = configuration(id: id, containerSize: CGSize(width: 200, height: 100))
        let resizedImage = configuration(id: id, imageSize: CGSize(width: 200, height: 50))
        let rotated = configuration(id: id, degrees: 90)
        let equivalentRotation = configuration(id: id, degrees: 360)

        // Then
        #expect(original != resizedContainer)
        #expect(original != resizedImage)
        #expect(original != rotated)
        #expect(original == equivalentRotation)
    }

    @Test("Game sidebar reservation reduces only the usable trailing viewport")
    func trailingViewportReservation() {
        let measuredSize = CGSize(width: 1_024, height: 768)

        let visibleSize = PhotoViewportReservation.effectiveContainerSize(
            measuredSize: measuredSize,
            trailingReservation: 324
        )
        let oversizedReservation = PhotoViewportReservation.effectiveContainerSize(
            measuredSize: measuredSize,
            trailingReservation: 2_000
        )

        #expect(visibleSize == CGSize(width: 700, height: 768))
        #expect(oversizedReservation == CGSize(width: 44, height: 768))
        #expect(
            PhotoViewportReservation.effectiveContainerSize(
                measuredSize: measuredSize,
                trailingReservation: .nan
            ) == measuredSize
        )
    }

    @Test("Pan bounds keep large content covering the viewport and center the smaller axis")
    func panBounds() {
        // Given
        let squareGeometry = ImageViewportGeometry(configuration: configuration(
            imageSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        ))
        let letterboxGeometry = ImageViewportGeometry(configuration: configuration(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        ))

        // When
        let squareOffset = squareGeometry.clampedOffset(CGPoint(x: 100, y: -500), at: 2)
        let letterboxOffset = letterboxGeometry.clampedOffset(CGPoint(x: 40, y: -500), at: letterboxGeometry.fitScale)

        // Then
        expectApproximately(squareOffset, CGPoint(x: 0, y: -100))
        expectApproximately(letterboxOffset, CGPoint(x: 0, y: 25))
    }

    @Test("Anchored zoom preserves the image point below the pinch anchor")
    func anchoredZoom() {
        // Given
        let geometry = ImageViewportGeometry(configuration: configuration(
            imageSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        ))
        let viewport = geometry.fitViewport
        let anchor = CGPoint(x: 25, y: 25)
        let imagePointBefore = imagePoint(at: anchor, viewport: viewport)

        // When
        let zoomedViewport = geometry.zoomedViewport(from: viewport, toScale: 2, anchor: anchor)
        let imagePointAfter = imagePoint(at: anchor, viewport: zoomedViewport)

        // Then
        expectApproximately(zoomedViewport, ImageViewport(scale: 2, offset: CGPoint(x: -25, y: -25)))
        expectApproximately(imagePointAfter, imagePointBefore)
    }

    @Test("Fill scale covers every container corner after rotation", arguments: FillRotationTestCase.cases)
    func fillScaleCoversContainer(testCase: FillRotationTestCase) {
        // Given
        let imageSize = CGSize(width: 160, height: 90)
        let containerSize = CGSize(width: 390, height: 844)
        let geometry = ImageViewportGeometry(configuration: configuration(
            imageSize: imageSize,
            containerSize: containerSize,
            degrees: testCase.degrees
        ))

        // When
        let scale = geometry.fillScale
        let localCorners = inverseRotatedContainerCorners(containerSize: containerSize, degrees: geometry.normalizedDegrees)

        // Then
        #expect(scale.isFinite)
        #expect(scale > 0)
        for corner in localCorners {
            #expect(abs(corner.x) <= imageSize.width * scale / 2 + TestTolerance.value)
            #expect(abs(corner.y) <= imageSize.height * scale / 2 + TestTolerance.value)
        }
    }
}

struct RotationTestCase: Sendable, CustomTestStringConvertible {
    let degrees: Double
    let normalizedDegrees: Double
    let expectedSize: CGSize

    var testDescription: String {
        "\(degrees) degrees"
    }

    static let cases: [Self] = [
        Self(degrees: 0, normalizedDegrees: 0, expectedSize: CGSize(width: 100, height: 50)),
        Self(degrees: 90, normalizedDegrees: 90, expectedSize: CGSize(width: 50, height: 100)),
        Self(degrees: 180, normalizedDegrees: 180, expectedSize: CGSize(width: 100, height: 50)),
        Self(degrees: 270, normalizedDegrees: 270, expectedSize: CGSize(width: 50, height: 100)),
        Self(degrees: 360, normalizedDegrees: 0, expectedSize: CGSize(width: 100, height: 50)),
        Self(degrees: -180, normalizedDegrees: 180, expectedSize: CGSize(width: 100, height: 50)),
        Self(
            degrees: 45,
            normalizedDegrees: 45,
            expectedSize: CGSize(width: 106.066_017, height: 106.066_017)
        ),
    ]
}

struct InvalidSizeTestCase: Sendable, CustomTestStringConvertible {
    let imageSize: CGSize
    let containerSize: CGSize
    let description: String

    var testDescription: String {
        description
    }

    static let cases: [Self] = [
        Self(imageSize: .zero, containerSize: CGSize(width: 100, height: 100), description: "zero image"),
        Self(imageSize: CGSize(width: 100, height: 100), containerSize: .zero, description: "zero container"),
        Self(
            imageSize: CGSize(width: CGFloat.nan, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            description: "NaN image"
        ),
        Self(
            imageSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: CGFloat.infinity, height: 100),
            description: "infinite container"
        ),
        Self(
            imageSize: CGSize(
                width: CGFloat.leastNonzeroMagnitude,
                height: CGFloat.leastNonzeroMagnitude
            ),
            containerSize: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            ),
            description: "overflowing ratio"
        ),
    ]
}

struct FillRotationTestCase: Sendable, CustomTestStringConvertible {
    let degrees: Double

    var testDescription: String {
        "\(degrees) degrees"
    }

    static let cases = [
        Self(degrees: 0),
        Self(degrees: 45),
        Self(degrees: 90),
        Self(degrees: 180),
        Self(degrees: 270),
    ]
}

private enum TestTolerance {
    static let value: CGFloat = 0.0001
}

private func configuration(
    id: UUID = UUID(),
    imageSize: CGSize = CGSize(width: 100, height: 50),
    containerSize: CGSize = CGSize(width: 100, height: 100),
    degrees: Double = 0
) -> ImageViewportConfiguration {
    ImageViewportConfiguration(
        id: id,
        imageSize: imageSize,
        containerSize: containerSize,
        degrees: degrees
    )
}

private func imagePoint(at anchor: CGPoint, viewport: ImageViewport) -> CGPoint {
    CGPoint(
        x: (anchor.x - viewport.offset.x) / viewport.scale,
        y: (anchor.y - viewport.offset.y) / viewport.scale
    )
}

private func inverseRotatedContainerCorners(containerSize: CGSize, degrees: Double) -> [CGPoint] {
    let radians = degrees * .pi / 180
    let cosine = CGFloat(cos(radians))
    let sine = CGFloat(sin(radians))
    let halfWidth = containerSize.width / 2
    let halfHeight = containerSize.height / 2
    let corners = [
        CGPoint(x: -halfWidth, y: -halfHeight),
        CGPoint(x: halfWidth, y: -halfHeight),
        CGPoint(x: -halfWidth, y: halfHeight),
        CGPoint(x: halfWidth, y: halfHeight),
    ]
    return corners.map { point in
        CGPoint(
            x: point.x * cosine + point.y * sine,
            y: -point.x * sine + point.y * cosine
        )
    }
}

private func expectOffsetWithinBounds(
    _ offset: CGPoint,
    scale: CGFloat,
    geometry: ImageViewportGeometry
) {
    #expect(geometry.clampedOffset(offset, at: scale) == offset)
}

private func expectApproximately(_ actual: CGFloat, _ expected: CGFloat) {
    #expect(abs(actual - expected) <= TestTolerance.value)
}

private func expectApproximately(_ actual: Double, _ expected: Double) {
    #expect(abs(actual - expected) <= Double(TestTolerance.value))
}

private func expectApproximately(_ actual: CGSize, _ expected: CGSize) {
    expectApproximately(actual.width, expected.width)
    expectApproximately(actual.height, expected.height)
}

private func expectApproximately(_ actual: CGPoint, _ expected: CGPoint) {
    expectApproximately(actual.x, expected.x)
    expectApproximately(actual.y, expected.y)
}

private func expectApproximately(_ actual: ImageViewport, _ expected: ImageViewport) {
    expectApproximately(actual.scale, expected.scale)
    expectApproximately(actual.offset, expected.offset)
}

private extension ImageViewport {
    var isFinite: Bool {
        scale.isFinite && offset.x.isFinite && offset.y.isFinite
    }
}
