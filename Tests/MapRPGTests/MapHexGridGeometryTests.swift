// @copyright André Trettin

import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_18 §5.6: a hex size below what the cell cap allows used to produce an empty
/// grid, which then erased the existing one; huge quotients could trap in `Int(_:)`.
@Suite("Hex grid geometry")
struct MapHexGridGeometryTests {
    @Test("A too-small size on a large map is raised to the smallest size that fits the cap")
    func smallSizeIsFittedInsteadOfEmptyingTheGrid() throws {
        let side = 8_192.0
        #expect((MapHexGridGeometry.cellCount(for: 20, width: side, height: side) ?? 0) > MapHexGridGeometry.maxCells)

        let fitted = MapHexGridGeometry.fittedSize(20, width: side, height: side)
        let count = try #require(MapHexGridGeometry.cellCount(for: fitted, width: side, height: side))
        #expect(fitted > 20)
        #expect(count <= MapHexGridGeometry.maxCells)

        let grid = MapHexGridGeometry.grid(for: fitted, in: CGRect(x: 0, y: 0, width: side, height: side))
        #expect(grid.count == count)
    }

    // CODE_AUDIT_21 §5.19: rebuilding the grid for a new scale hid everything revealed.
    @Test("A rebuilt grid keeps the revealed area")
    func rebuiltGridKeepsRevealedArea() {
        let rect = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        var previous = MapHexGridGeometry.grid(for: 100, in: rect)
        // Reveal the left half.
        for index in previous.indices {
            let centreX = previous[index].coordinates.map(\.x).reduce(0, +) / CGFloat(previous[index].coordinates.count)
            previous[index].isShown = centreX < 500
        }
        let grid = MapHexGridGeometry.grid(for: 40, in: rect)

        let carried = MapHexGridGeometry.carryingRevealedArea(from: previous, to: grid)

        #expect(carried.count == grid.count)
        #expect(carried.map(\.id) == grid.map(\.id))
        func centreX(_ entry: MapEntryModel) -> CGFloat {
            entry.coordinates.map(\.x).reduce(0, +) / CGFloat(entry.coordinates.count)
        }
        // Well inside the revealed half every new cell is shown, well outside none is; only
        // cells on the border between old cells can go either way.
        let inside = carried.filter { centreX($0) < 300 }
        let outside = carried.filter { centreX($0) > 700 }
        #expect(!inside.isEmpty)
        #expect(inside.count(where: \.isShown) == inside.count)
        #expect(outside.count(where: \.isShown) == 0)
    }

    @Test("A grid replacing one with nothing revealed starts hidden")
    func nothingRevealedCarriesNothing() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 600)
        let previous = MapHexGridGeometry.grid(for: 80, in: rect)
        let grid = MapHexGridGeometry.grid(for: 50, in: rect)

        #expect(MapHexGridGeometry.carryingRevealedArea(from: previous, to: grid).allSatisfy { !$0.isShown })
    }

    @Test("A size that already fits is kept")
    func fittingSizeIsKept() {
        #expect(MapHexGridGeometry.fittedSize(80, width: 2_048, height: 1_536) == 80)
    }

    @Test("Degenerate and overflowing inputs produce no grid instead of trapping")
    func degenerateInputsDoNotTrap() {
        let rect = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        #expect(MapHexGridGeometry.grid(for: 0, in: rect).isEmpty)
        #expect(MapHexGridGeometry.grid(for: .nan, in: rect).isEmpty)
        #expect(MapHexGridGeometry.grid(for: 1e-300, in: rect).isEmpty)
        #expect(MapHexGridGeometry.dimensions(for: 1e-300, width: 1e300, height: 1e300) == nil)
    }
}
