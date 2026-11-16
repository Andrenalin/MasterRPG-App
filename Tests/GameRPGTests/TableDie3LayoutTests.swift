// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Layout of the d3 on the d6 cube")
struct TableDie3LayoutTests {
    @Test("Opposite faces of the cube show the same number, and 1, 2 and 3 each appear twice")
    func numbers() {
        #expect(TableDie3Layout.number(forPips: 1) == 1)
        #expect(TableDie3Layout.number(forPips: 6) == 1)
        #expect(TableDie3Layout.number(forPips: 2) == 2)
        #expect(TableDie3Layout.number(forPips: 5) == 2)
        #expect(TableDie3Layout.number(forPips: 3) == 3)
        #expect(TableDie3Layout.number(forPips: 4) == 3)
        let numbers = TableDie6Geometry.faces.map { TableDie3Layout.number(forPips: $0.number) }.sorted()
        #expect(numbers == [1, 1, 2, 2, 3, 3])
    }

    @Test("A value is shown by the cube face with that many pips, and the d3 shows that value on it")
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
