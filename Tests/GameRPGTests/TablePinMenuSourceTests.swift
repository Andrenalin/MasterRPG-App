// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import GameRPG

@Suite("Pin action popover source on the 3D table")
struct TablePinMenuSourceTests {
    @Test("A box has eight distinct corners spanning its bounds")
    func boxCorners() {
        let corners = TablePinMenuSource.corners(
            min: SIMD3<Float>(-1, 0, 2),
            max: SIMD3<Float>(1, 0.5, 4)
        )

        #expect(corners.count == 8)
        #expect(Set(corners.map { [$0.x, $0.y, $0.z] }).count == 8)
        #expect(corners.map(\.x).min() == -1)
        #expect(corners.map(\.x).max() == 1)
        #expect(corners.map(\.y).max() == 0.5)
        #expect(corners.map(\.z).max() == 4)
    }

    @Test("The frame encloses every projected corner")
    func frameEnclosesProjectedCorners() {
        let frame = TablePinMenuSource.frame(enclosing: [
            CGPoint(x: 120, y: 80),
            CGPoint(x: 160, y: 95),
            CGPoint(x: 135, y: 60),
            CGPoint(x: 150, y: 110)
        ])

        #expect(frame == CGRect(x: 120, y: 60, width: 40, height: 50))
    }

    @Test("A pin behind the camera or without a finite projection has no frame")
    func unprojectablePinHasNoFrame() {
        #expect(TablePinMenuSource.frame(enclosing: []) == nil)
        #expect(TablePinMenuSource.frame(enclosing: [CGPoint(x: 10, y: 10), nil]) == nil)
        #expect(TablePinMenuSource.frame(enclosing: [CGPoint(x: 10, y: CGFloat.infinity)]) == nil)
        #expect(TablePinMenuSource.frame(enclosing: [CGPoint(x: CGFloat.nan, y: 10)]) == nil)
    }

    @Test("Sub-point projection noise is not a visible change; movement and another pin are")
    func visibleChange() {
        let pinId = UUID()
        let source = TablePinMenuSource(pinId: pinId, frame: CGRect(x: 100, y: 100, width: 40, height: 20))

        #expect(source.differsVisibly(from: nil))
        #expect(!source.differsVisibly(from: source))
        #expect(!source.differsVisibly(
            from: TablePinMenuSource(pinId: pinId, frame: CGRect(x: 100.2, y: 99.9, width: 40, height: 20))
        ))
        #expect(source.differsVisibly(
            from: TablePinMenuSource(pinId: pinId, frame: CGRect(x: 101, y: 100, width: 40, height: 20))
        ))
        #expect(source.differsVisibly(
            from: TablePinMenuSource(pinId: pinId, frame: CGRect(x: 100, y: 100, width: 42, height: 20))
        ))
        #expect(source.differsVisibly(from: TablePinMenuSource(pinId: UUID(), frame: source.frame)))
    }
}
#endif
