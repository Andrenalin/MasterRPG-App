// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import PhotoRPG
import SwiftUI
import Testing

@testable import MapRPG

@Suite("Map editor viewport transforms")
@MainActor
struct MapEditorViewportTransformTests {
    @Test("Magnification preserves the canvas point below its anchor")
    func magnificationPreservesAnchor() {
        // Given
        let baseline = MapViewportTransform(
            scale: 2,
            offset: CGPoint(x: -100, y: -50)
        )
        let anchor = CGPoint(x: 200, y: 150)
        let canvasPointBefore = canvasPoint(at: anchor, transform: baseline)

        // When
        let result = baseline.magnified(by: 1.5, around: anchor)

        // Then
        expect(result.scale, equals: 3)
        expect(result.offset, equals: CGPoint(x: -250, y: -150))
        expect(canvasPoint(at: anchor, transform: result), equals: canvasPointBefore)
    }

    @Test("Native magnification anchor is converted from viewport unit coordinates")
    func nativeMagnificationAnchor() {
        // Given
        let sut = makeModel(containerSize: CGSize(width: 400, height: 300))
        let baseline = MapViewportTransform(
            scale: 0.5,
            offset: CGPoint(x: -20, y: 30)
        )

        // When
        let result = sut.magnifiedViewportTransform(
            from: baseline,
            magnification: 2,
            startAnchor: UnitPoint(x: 0.25, y: 0.75)
        )

        // Then
        expect(result.scale, equals: 1)
        expect(result.offset, equals: CGPoint(x: -140, y: -165))
    }

    @Test("Consecutive gestures each use a committed absolute baseline")
    func consecutiveMagnificationsUseCommittedBaseline() {
        // Given
        let sut = makeModel()
        sut.commitViewportTransform(MapViewportTransform(
            scale: 0.5,
            offset: CGPoint(x: 10, y: 20)
        ))

        // When
        let firstBaseline = sut.viewportTransform
        let firstPreview = sut.magnifiedViewportTransform(
            from: firstBaseline,
            magnification: 1.5,
            startAnchor: .center
        )

        // Then: deriving a preview does not mutate committed model state.
        expect(sut.viewportTransform.scale, equals: 0.5)
        expect(sut.viewportTransform.offset, equals: CGPoint(x: 10, y: 20))

        // When
        sut.commitViewportTransform(firstPreview)
        let secondBaseline = sut.viewportTransform
        let secondPreview = sut.magnifiedViewportTransform(
            from: secondBaseline,
            magnification: 2,
            startAnchor: .center
        )

        // Then
        expect(firstPreview.scale, equals: 0.75)
        expect(secondPreview.scale, equals: 1.5)
    }

    @Test("Double-tap zoom calculation is side-effect free")
    func zoomInDoesNotMutateModel() {
        // Given
        let sut = makeModel(containerSize: CGSize(width: 400, height: 300))
        let baseline = MapViewportTransform(
            scale: 0.5,
            offset: CGPoint(x: 20, y: 30)
        )
        sut.commitViewportTransform(baseline)

        // When
        let result = sut.zoomIn(at: CGPoint(x: 100, y: 150))

        // Then
        expect(sut.viewportTransform.scale, equals: baseline.scale)
        expect(sut.viewportTransform.offset, equals: baseline.offset)
        expect(result.0, equals: 2)
        expect(result.1, equals: CGPoint(x: -120, y: -330))
    }

    @Test("Pan preview retains the existing overscroll bounds")
    func panPreviewIsConstrained() {
        // Given
        let sut = makeModel(containerSize: CGSize(width: 400, height: 300))
        let baseline = MapViewportTransform(scale: 1, offset: .zero)

        // When
        let result = sut.pannedViewportTransform(
            from: baseline,
            translation: CGSize(width: 1_000, height: -2_000)
        )

        // Then
        expect(result.scale, equals: 1)
        expect(result.offset, equals: CGPoint(x: 300, y: -800))
    }

    @Test("Legacy magnification API also uses one stable baseline")
    func legacyMagnificationUsesStableBaseline() {
        // Given
        let sut = makeModel(containerSize: CGSize(width: 400, height: 300))
        sut.commitViewportTransform(MapViewportTransform(
            scale: 0.5,
            offset: CGPoint(x: 20, y: 30)
        ))

        // When
        sut.updateScale(1.1, updateLast: true)
        sut.updateScale(1.5, updateLast: false)

        // Then
        expect(sut.viewportTransform.scale, equals: 0.75)
        expect(sut.viewportTransform.offset, equals: CGPoint(x: -70, y: -30))
    }
}

private extension MapEditorViewportTransformTests {
    func makeModel(
        containerSize: CGSize = CGSize(width: 400, height: 300)
    ) -> MapEditorModel {
        MapEditorModel(
            map: MapModel(
                id: UUID(),
                name: "Viewport Test Map",
                width: 1_200,
                height: 800
            ),
            image: AKImage(),
            photoDegrees: 0,
            containerSize: containerSize
        )
    }

    func canvasPoint(
        at viewportPoint: CGPoint,
        transform: MapViewportTransform
    ) -> CGPoint {
        CGPoint(
            x: (viewportPoint.x - transform.offset.x) / transform.scale,
            y: (viewportPoint.y - transform.offset.y) / transform.scale
        )
    }

    func expect(
        _ actual: CGPoint,
        equals expected: CGPoint,
        tolerance: CGFloat = 0.000_1
    ) {
        expect(actual.x, equals: expected.x, tolerance: tolerance)
        expect(actual.y, equals: expected.y, tolerance: tolerance)
    }

    func expect(
        _ actual: CGFloat,
        equals expected: CGFloat,
        tolerance: CGFloat = 0.000_1
    ) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
#endif
