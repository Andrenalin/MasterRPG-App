// @copyright André Trettin

import CoreGraphics
import Testing

@testable import PhotoRPG

@Suite("Async thumbnail image quality")
struct AsyncThumbnailTests {
    @Test(
        "Full images are reserved for presentations at least 160 points wide or high",
        arguments: [
            AsyncThumbnailQualityTestCase(size: CGSize(width: 64, height: 64), expected: false),
            AsyncThumbnailQualityTestCase(size: CGSize(width: 128, height: 128), expected: false),
            AsyncThumbnailQualityTestCase(size: CGSize(width: 159, height: 80), expected: false),
            AsyncThumbnailQualityTestCase(size: CGSize(width: 160, height: 80), expected: true),
            AsyncThumbnailQualityTestCase(size: CGSize(width: 80, height: 160), expected: true),
        ]
    )
    func fullImageCutoff(testCase: AsyncThumbnailQualityTestCase) {
        #expect(AsyncThumbnail.shouldUseFullImage(for: testCase.size) == testCase.expected)
    }
}

struct AsyncThumbnailQualityTestCase: Sendable {
    let size: CGSize
    let expected: Bool
}
