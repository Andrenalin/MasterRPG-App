// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Layout of the d3 on the d6 mesh")
struct TableDie3LayoutTests {
    @Test("Opposite faces of the d6 show the same number, and 1, 2 and 3 each appear twice")
    func numbers() {
        #expect(TableDie3Layout.number(forPips: 1) == 1)
        #expect(TableDie3Layout.number(forPips: 6) == 1)
        #expect(TableDie3Layout.number(forPips: 2) == 2)
        #expect(TableDie3Layout.number(forPips: 5) == 2)
        #expect(TableDie3Layout.number(forPips: 3) == 3)
        #expect(TableDie3Layout.number(forPips: 4) == 3)
        let numbers = TableDie3Layout.islands.map(\.number).sorted()
        #expect(numbers == [1, 1, 2, 2, 3, 3])
    }

    @Test("Every pip count of the d6 has exactly one island, inside the atlas")
    func islands() {
        #expect(TableDie3Layout.islands.map(\.pips).sorted() == [1, 2, 3, 4, 5, 6])
        for island in TableDie3Layout.islands {
            #expect(island.center.x > 0 && island.center.x < 1)
            #expect(island.center.y > 0 && island.center.y < 1)
        }
    }

    @Test("A value is shown by the d6 face with that many pips, and the d3 shows that value on it")
    func faceUp() {
        for value in 1 ... 3 {
            let face = TableDie3Layout.faceUp(forValue: value)
            #expect(face == value)
            #expect(face.map(TableDie3Layout.number(forPips:)) == value)
        }
        #expect(TableDie3Layout.faceUp(forValue: 0) == nil)
        #expect(TableDie3Layout.faceUp(forValue: 4) == nil)
    }
}
#endif
