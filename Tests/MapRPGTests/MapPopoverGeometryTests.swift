// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

@Suite("Map pin popover geometry")
struct MapPopoverGeometryTests {
    private let viewport = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    private let contentSize = CGSize(width: 80, height: 320)

    @Test("Popover prefers the trailing side and points at the pin")
    func prefersTrailing() {
        // Given
        let source = CGRect(x: 400, y: 380, width: 40, height: 40)

        // When
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: contentSize,
            viewport: viewport
        )

        // Then
        #expect(placement.isValid)
        #expect(placement.isFullyVisible)
        #expect(placement.side == .trailing)
        #expect(placement.frame.minX == source.maxX)
        #expect(placement.frame.size == CGSize(
            width: contentSize.width + MapPopoverGeometry.arrowLength,
            height: contentSize.height
        ))
        #expect(placement.frame.minY + placement.arrowOffset == source.midY)
    }

    @Test("Popover flips to the leading side at the trailing viewport edge")
    func flipsToLeading() {
        // Given
        let source = CGRect(x: 940, y: 380, width: 40, height: 40)

        // When
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: contentSize,
            viewport: viewport
        )

        // Then
        #expect(placement.side == .leading)
        #expect(placement.frame.maxX == source.minX)
        #expect(placement.isFullyVisible)
    }

    @Test("Popover stays inside the viewport near the top edge and keeps its arrow off the corners")
    func clampsVertically() {
        // Given
        let source = CGRect(x: 400, y: 0, width: 40, height: 40)

        // When
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: contentSize,
            viewport: viewport
        )

        // Then
        #expect(placement.side == .trailing)
        #expect(placement.frame.minY == MapPopoverGeometry.edgeInset)
        #expect(placement.isFullyVisible)
        let minimumOffset = MapPopoverGeometry.cornerRadius + MapPopoverGeometry.arrowWidth / 2
        #expect(placement.arrowOffset >= minimumOffset)
        #expect(placement.arrowOffset <= placement.frame.height - minimumOffset)
    }

    @Test("Popover uses the side with the most room when no side fits")
    func fallsBackToRoomiestSide() {
        // Given
        let narrowViewport = CGRect(x: 0, y: 0, width: 300, height: 200)
        let source = CGRect(x: 110, y: 80, width: 40, height: 40)

        // When
        let placement = MapPopoverGeometry.placement(
            source: source,
            contentSize: CGSize(width: 200, height: 150),
            viewport: narrowViewport
        )

        // Then
        #expect(placement.isValid)
        #expect(placement.side == .trailing)
        // Clamped back into the viewport, the panel overlaps its pin.
        #expect(placement.isFullyVisible)
        #expect(placement.frame.intersects(source))
    }

    @Test("Popover is invalid until its content has been measured")
    func invalidWithoutContentSize() {
        // When
        let placement = MapPopoverGeometry.placement(
            source: CGRect(x: 400, y: 380, width: 40, height: 40),
            contentSize: .zero,
            viewport: viewport
        )

        // Then
        #expect(!placement.isValid)
    }
}
#endif
