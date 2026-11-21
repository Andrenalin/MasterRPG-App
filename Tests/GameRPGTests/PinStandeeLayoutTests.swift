// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Pin standee layout")
struct PinStandeeLayoutTests {
    private let diameter: Float = 0.04

    @Test("A tall figure is limited by the height")
    func tallFigureFitsHeight() {
        let layout = PinStandeeLayout(aspect: 0.5, diameter: diameter)

        #expect(abs(layout.height - diameter * PinStandeeLayout.maximumHeightFactor) < 1e-6)
        #expect(abs(layout.width - layout.height * 0.5) < 1e-6)
        #expect(layout.width <= diameter * PinStandeeLayout.maximumWidthFactor)
    }

    @Test("A wide creature is limited by the width and keeps its aspect")
    func wideCreatureFitsWidth() {
        let layout = PinStandeeLayout(aspect: 3, diameter: diameter)

        #expect(abs(layout.width - diameter * PinStandeeLayout.maximumWidthFactor) < 1e-6)
        #expect(abs(layout.width / layout.height - 3) < 1e-4)
        #expect(layout.height <= diameter * PinStandeeLayout.maximumHeightFactor)
    }

    @Test("An invalid aspect falls back to a square instead of a degenerate mesh", arguments: [Float.nan, 0, -2, .infinity])
    func invalidAspectFallsBack(aspect: Float) {
        let layout = PinStandeeLayout(aspect: aspect, diameter: diameter)

        #expect(layout.width > 0)
        #expect(layout.height > 0)
        #expect(layout.width.isFinite && layout.height.isFinite)
    }

    @Test("The hit box starts at the table surface and covers the figure and the base")
    func collisionBoxCoversFigure() {
        let layout = PinStandeeLayout(aspect: 0.6, diameter: diameter)
        let size = layout.collisionSize(diameter: diameter)
        let bottom = layout.collisionCenterY() - size.y / 2
        let top = layout.collisionCenterY() + size.y / 2

        #expect(abs(bottom) < 1e-6)
        #expect(top >= PinStandeeLayout.bottomY + layout.height - 1e-6)
        #expect(size.x >= diameter)
        #expect(size.z == diameter)
    }

    @Test("A fallen figure is centred on the base and sits between the disc and the death marks")
    func fallenFigureIsCentred() {
        let layout = PinStandeeLayout(aspect: 0.5, diameter: diameter)

        #expect(abs(layout.fallenRootZ - layout.height / 2) < 1e-6)
        #expect(PinStandeeLayout.fallenY > PinStandeeLayout.bottomY)
        // The death-mark bars are at local Y 0.006 with a 1 mm height.
        #expect(PinStandeeLayout.fallenY + PinStandeeLayout.faceOffset < 0.0055)
    }
}
#endif
