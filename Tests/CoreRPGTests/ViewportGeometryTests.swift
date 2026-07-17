// @copyright André Trettin

import CoreGraphics
import Foundation
import Testing

@testable import CoreRPG

@Suite("Shared viewport geometry")
struct ViewportGeometryTests {
    @Test("Aspect fit centers complete content")
    func aspectFit() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        expectApproximately(geometry.fitScale, 0.5)
        expectApproximately(
            geometry.fitTransform,
            ViewportTransform(scale: 0.5, offset: CGPoint(x: 0, y: 25))
        )
        expectApproximately(geometry.maximumScale, 4)
    }

    @Test("Contained pan covers a large axis and centers a small axis")
    func containedPan() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            panPolicy: .contained
        )

        let transform = geometry.constrained(
            ViewportTransform(scale: 1, offset: CGPoint(x: 80, y: -200))
        )

        expectApproximately(transform.offset, CGPoint(x: 0, y: 0))
    }

    @Test("Recoverable pan keeps the configured strip visible at every edge")
    func minimumVisiblePan() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            panPolicy: .minimumVisible(44)
        )

        let topLeft = geometry.constrained(
            ViewportTransform(scale: 1, offset: CGPoint(x: -1_000, y: -1_000))
        )
        let bottomRight = geometry.constrained(
            ViewportTransform(scale: 1, offset: CGPoint(x: 1_000, y: 1_000))
        )

        expectApproximately(topLeft.offset, CGPoint(x: -156, y: -56))
        expectApproximately(bottomRight.offset, CGPoint(x: 56, y: 56))
    }

    @Test("Anchored magnification preserves the logical point below the anchor")
    func anchoredMagnification() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )
        let anchor = CGPoint(x: 25, y: 25)
        let before = geometry.contentPoint(fromViewport: anchor, transform: geometry.fitTransform)

        let magnified = geometry.magnified(
            from: geometry.fitTransform,
            magnification: 2,
            anchor: anchor
        )
        let after = geometry.contentPoint(fromViewport: anchor, transform: magnified)

        expectApproximately(magnified, ViewportTransform(scale: 2, offset: CGPoint(x: -25, y: -25)))
        expectApproximately(after, before)
    }

    @Test("A simultaneous pinch and pan is derived from one immutable baseline")
    func simultaneousPinchAndPan() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            panPolicy: .minimumVisible(44)
        )

        let transform = geometry.interacting(
            from: geometry.fitTransform,
            translation: CGSize(width: 10, height: 20),
            magnification: 2,
            anchor: CGPoint(x: 25, y: 25)
        )

        expectApproximately(transform, ViewportTransform(scale: 2, offset: CGPoint(x: -15, y: -5)))
    }

    @Test("Double tap toggles between four times fit and fit")
    func doubleTap() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )

        let zoomed = geometry.doubleTapped(from: geometry.fitTransform, at: CGPoint(x: 50, y: 0))
        let reset = geometry.doubleTapped(from: zoomed, at: CGPoint(x: 50, y: 50))

        expectApproximately(zoomed.scale, 2)
        expectApproximately(reset, geometry.fitTransform)
    }

    @Test("Viewport and logical coordinates round trip")
    func coordinateRoundTrip() {
        let geometry = makeGeometry(
            contentSize: CGSize(width: 300, height: 200),
            containerSize: CGSize(width: 120, height: 100),
            panPolicy: .minimumVisible(44)
        )
        let transform = geometry.constrained(
            ViewportTransform(scale: 1.5, offset: CGPoint(x: -70, y: -25))
        )
        let logicalPoint = CGPoint(x: 123, y: 87)

        let viewportPoint = geometry.viewportPoint(fromContent: logicalPoint, transform: transform)
        let roundTrip = geometry.contentPoint(fromViewport: viewportPoint, transform: transform)

        expectApproximately(roundTrip, logicalPoint)
    }

    @Test("Resize refits a fitted viewport and preserves a zoomed focal point")
    func resizePreservation() {
        let id = UUID()
        let oldConfiguration = makeConfiguration(
            id: id,
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 100, height: 100),
            panPolicy: .minimumVisible(44)
        )
        let oldGeometry = ViewportGeometry(configuration: oldConfiguration)
        let newGeometry = makeGeometry(
            id: id,
            contentSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 160, height: 100),
            panPolicy: .minimumVisible(44)
        )

        let refitted = newGeometry.resizedTransform(
            from: oldGeometry.fitTransform,
            previousConfiguration: oldConfiguration
        )
        let zoomed = ViewportTransform(scale: 1.5, offset: CGPoint(x: -70, y: -25))
        let oldFocus = CGPoint(x: 50, y: 50)
        let newFocus = CGPoint(x: 80, y: 50)
        let logicalFocus = oldGeometry.contentPoint(fromViewport: oldFocus, transform: zoomed)
        let preserved = newGeometry.resizedTransform(
            from: zoomed,
            previousConfiguration: oldConfiguration,
            oldAnchor: oldFocus,
            newAnchor: newFocus
        )

        expectApproximately(refitted, newGeometry.fitTransform)
        expectApproximately(
            newGeometry.contentPoint(fromViewport: newFocus, transform: preserved),
            logicalFocus
        )
        expectApproximately(preserved.scale, zoomed.scale)
    }

    @Test("Invalid geometry always returns finite transforms and points")
    func invalidGeometry() {
        let configuration = ViewportConfiguration(
            id: UUID(),
            contentSize: CGSize(width: CGFloat.nan, height: CGFloat.infinity),
            containerSize: CGSize(width: -1, height: 0),
            maximumScaleMultiplier: CGFloat.nan,
            panPolicy: .minimumVisible(CGFloat.infinity)
        )
        let geometry = ViewportGeometry(configuration: configuration)
        let invalid = ViewportTransform(
            scale: CGFloat.nan,
            offset: CGPoint(x: CGFloat.infinity, y: CGFloat.nan)
        )

        let constrained = geometry.constrained(invalid)
        let magnified = geometry.magnified(
            from: invalid,
            magnification: CGFloat.infinity,
            anchor: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)
        )
        let logicalPoint = geometry.contentPoint(
            fromViewport: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
            transform: invalid
        )

        #expect(constrained.isFinite)
        #expect(magnified.isFinite)
        #expect(logicalPoint.isFinite)
    }

    @Test("Rotation normalization and bounds support cardinal and arbitrary angles")
    func rotation() {
        #expect(ViewportGeometry.normalize(rotationDegrees: -90) == 270)
        #expect(ViewportGeometry.normalize(rotationDegrees: Double.nan) == 0)
        expectApproximately(
            ViewportGeometry.rotatedContentSize(
                CGSize(width: 100, height: 50),
                rotationDegrees: 90
            ),
            CGSize(width: 50, height: 100)
        )
        expectApproximately(
            ViewportGeometry.rotatedContentSize(
                CGSize(width: 100, height: 50),
                rotationDegrees: 45
            ),
            CGSize(width: 106.066_017, height: 106.066_017)
        )

        let contentSize = CGSize(width: 100, height: 50)
        let logicalPoint = CGPoint(x: 20, y: 10)
        let rotatedPoint = ViewportGeometry.rotatedPoint(
            fromContent: logicalPoint,
            contentSize: contentSize,
            rotationDegrees: 270
        )
        let roundTrip = ViewportGeometry.contentPoint(
            fromRotated: rotatedPoint,
            contentSize: contentSize,
            rotationDegrees: 270
        )
        expectApproximately(roundTrip, logicalPoint)
    }

    @MainActor @Test("Viewport model commits constrained state and resets atomically")
    func viewportModel() {
        let configuration = makeConfiguration(
            contentSize: CGSize(width: 100, height: 100),
            containerSize: CGSize(width: 100, height: 100)
        )
        let model = ViewportModel(configuration: configuration)

        model.commit(ViewportTransform(scale: 2, offset: CGPoint(x: -30, y: -40)))
        expectApproximately(model.transform, ViewportTransform(scale: 2, offset: CGPoint(x: -30, y: -40)))
        model.reset()

        expectApproximately(model.transform, model.geometry.fitTransform)
        #expect(model.isAtFit)
    }
}

private enum ViewportTestTolerance {
    static let value: CGFloat = 0.0001
}

private func makeConfiguration(
    id: UUID = UUID(),
    contentSize: CGSize,
    containerSize: CGSize,
    maximumScaleMultiplier: CGFloat = 8,
    panPolicy: ViewportPanPolicy = .contained
) -> ViewportConfiguration {
    ViewportConfiguration(
        id: id,
        contentSize: contentSize,
        containerSize: containerSize,
        maximumScaleMultiplier: maximumScaleMultiplier,
        panPolicy: panPolicy
    )
}

private func makeGeometry(
    id: UUID = UUID(),
    contentSize: CGSize,
    containerSize: CGSize,
    maximumScaleMultiplier: CGFloat = 8,
    panPolicy: ViewportPanPolicy = .contained
) -> ViewportGeometry {
    ViewportGeometry(configuration: makeConfiguration(
        id: id,
        contentSize: contentSize,
        containerSize: containerSize,
        maximumScaleMultiplier: maximumScaleMultiplier,
        panPolicy: panPolicy
    ))
}

private func expectApproximately(_ actual: CGFloat, _ expected: CGFloat) {
    #expect(abs(actual - expected) <= ViewportTestTolerance.value)
}

private func expectApproximately(_ actual: CGSize, _ expected: CGSize) {
    expectApproximately(actual.width, expected.width)
    expectApproximately(actual.height, expected.height)
}

private func expectApproximately(_ actual: CGPoint, _ expected: CGPoint) {
    expectApproximately(actual.x, expected.x)
    expectApproximately(actual.y, expected.y)
}

private func expectApproximately(_ actual: ViewportTransform, _ expected: ViewportTransform) {
    expectApproximately(actual.scale, expected.scale)
    expectApproximately(actual.offset, expected.offset)
}

private extension ViewportTransform {
    var isFinite: Bool {
        scale.isFinite && offset.isFinite
    }
}

private extension CGPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}
