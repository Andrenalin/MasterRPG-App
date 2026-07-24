// @copyright André Trettin

import Testing

@testable import RolePlayGameKit

@Suite("macOS split content column width")
struct TabbedSplitContentColumnWidthTests {
    @Test("A user-resized list width is retained exactly")
    func retainsMeasuredWidth() {
        // Given
        let measuredWidth = 427.25

        // When
        let updatedWidth = TabbedSplitContentColumnWidth.updatedWidth(
            measuredWidth: measuredWidth,
            currentWidth: TabbedSplitContentColumnWidth.defaultWidth
        )

        // Then
        #expect(updatedWidth == measuredWidth)
    }

    @Test("Restored widths remain inside the split view limits")
    func normalizesRestoredWidth() {
        // Given
        let widthBelowMinimum = 120.0
        let widthAboveMaximum = 900.0

        // When
        let minimumWidth = TabbedSplitContentColumnWidth.normalized(widthBelowMinimum)
        let maximumWidth = TabbedSplitContentColumnWidth.normalized(widthAboveMaximum)

        // Then
        #expect(minimumWidth == TabbedSplitContentColumnWidth.minimumWidth)
        #expect(maximumWidth == TabbedSplitContentColumnWidth.maximumWidth)
    }

    @Test("Invalid and layout-noise measurements do not replace the saved width")
    func ignoresInvalidAndInsignificantMeasurements() {
        // Given
        let currentWidth = 427.25

        // When
        let invalidWidth = TabbedSplitContentColumnWidth.updatedWidth(
            measuredWidth: .nan,
            currentWidth: currentWidth
        )
        let layoutNoise = TabbedSplitContentColumnWidth.updatedWidth(
            measuredWidth: currentWidth + 0.25,
            currentWidth: currentWidth
        )

        // Then
        #expect(invalidWidth == nil)
        #expect(layoutNoise == nil)
    }
}
