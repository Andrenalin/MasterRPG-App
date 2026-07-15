// @copyright André Trettin

import CoreGraphics
import Foundation
import Testing

@testable import CoreRPG

@Suite("Drag tap classifier")
struct DragTapClassifierTests {
    private static let maximumInterval: TimeInterval = 0.3
    private static let maximumDistance: CGFloat = 44

    @Test("The first tap is never a double tap")
    func firstTapIsNotDoubleTap() {
        // Given
        var classifier = DragTapClassifier()

        // When
        let isDoubleTap = classifier.registerRelease(
            at: .init(x: 100, y: 100),
            timestamp: 1,
            didDrag: false,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )

        // Then
        #expect(!isDoubleTap)
    }

    @Test(
        "A second tap must be timely and nearby",
        arguments: SecondTapTestCase.cases
    )
    func secondTapClassification(testCase: SecondTapTestCase) {
        // Given
        var classifier = DragTapClassifier()
        _ = classifier.registerRelease(
            at: .init(x: 100, y: 100),
            timestamp: 1,
            didDrag: false,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )

        // When
        let isDoubleTap = classifier.registerRelease(
            at: testCase.location,
            timestamp: testCase.timestamp,
            didDrag: false,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )

        // Then
        #expect(isDoubleTap == testCase.expectedResult)
    }

    @Test("Dragging clears a pending first tap")
    func dragClearsPendingTap() {
        // Given
        var classifier = DragTapClassifier()
        _ = classifier.registerRelease(
            at: .init(x: 100, y: 100),
            timestamp: 1,
            didDrag: false,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )

        // When
        let dragResult = classifier.registerRelease(
            at: .init(x: 101, y: 101),
            timestamp: 1.1,
            didDrag: true,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )
        let tapAfterDragResult = classifier.registerRelease(
            at: .init(x: 101, y: 101),
            timestamp: 1.2,
            didDrag: false,
            didMagnify: false,
            maximumInterval: Self.maximumInterval,
            maximumDistance: Self.maximumDistance
        )

        // Then
        #expect(!dragResult)
        #expect(!tapAfterDragResult)
    }
}

struct SecondTapTestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let timestamp: TimeInterval
    let location: CGPoint
    let expectedResult: Bool

    var testDescription: String { name }

    static let cases = [
        SecondTapTestCase(
            name: "timely and nearby",
            timestamp: 1.2,
            location: .init(x: 110, y: 110),
            expectedResult: true
        ),
        SecondTapTestCase(
            name: "too late",
            timestamp: 1.31,
            location: .init(x: 100, y: 100),
            expectedResult: false
        ),
        SecondTapTestCase(
            name: "too far away",
            timestamp: 1.2,
            location: .init(x: 145, y: 100),
            expectedResult: false
        )
    ]
}
