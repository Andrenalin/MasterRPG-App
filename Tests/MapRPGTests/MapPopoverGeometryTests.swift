// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

@Suite("Map popover geometry")
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
        #expect(placement.frame.minX == source.maxX + MapPopoverGeometry.sourceGap)
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
        #expect(placement.frame.maxX == source.minX - MapPopoverGeometry.sourceGap)
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

    @Test("Needle popover sits in a row above the needle and points down at its head")
    func needleRowPrefersTop() {
        // Given
        let needle = CGRect(x: 478, y: 300, width: 44, height: 110)
        let rowSize = CGSize(width: 112, height: 56)

        // When
        let placement = MapPopoverGeometry.placement(
            source: needle,
            contentSize: rowSize,
            viewport: viewport,
            preferredSides: [.top, .bottom]
        )

        // Then
        #expect(placement.side == .top)
        #expect(placement.isFullyVisible)
        #expect(placement.frame.maxY == needle.minY - MapPopoverGeometry.sourceGap)
        #expect(placement.frame.size == CGSize(
            width: rowSize.width,
            height: rowSize.height + MapPopoverGeometry.arrowLength
        ))
        #expect(placement.frame.minX + placement.arrowOffset == needle.midX)
    }

    @Test("Needle popover flips below the needle tip when there is no room above")
    func needleRowFlipsBelow() {
        // Given
        let needle = CGRect(x: 478, y: 20, width: 44, height: 110)

        // When
        let placement = MapPopoverGeometry.placement(
            source: needle,
            contentSize: CGSize(width: 112, height: 56),
            viewport: viewport,
            preferredSides: [.top, .bottom]
        )

        // Then
        #expect(placement.side == .bottom)
        #expect(placement.isFullyVisible)
        #expect(placement.frame.minY == needle.maxY + MapPopoverGeometry.sourceGap)
        #expect(!placement.frame.intersects(needle))
    }

    @Test("Needle popover never moves beside the needle, and stays inside the viewport at a side edge")
    func needleRowStaysVerticalAtSideEdge() {
        // Given
        let needle = CGRect(x: 0, y: 300, width: 44, height: 110)

        // When
        let placement = MapPopoverGeometry.placement(
            source: needle,
            contentSize: CGSize(width: 112, height: 56),
            viewport: viewport,
            preferredSides: [.top, .bottom]
        )

        // Then
        #expect(placement.side == .top)
        #expect(placement.frame.minX == MapPopoverGeometry.edgeInset)
        #expect(placement.isFullyVisible)
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
