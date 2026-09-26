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
