// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
@testable import CharacterRPG
@testable import DiceRPG
import Foundation
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG
import Testing

/// The "base|modifier" convention of a Character value, as the battle health
/// ring reads it: the base is the maximum, base plus modifier the current
/// amount.
@Suite("Character value base and current")
@MainActor
struct GameValueBaseAndCurrentTests {
    @Test("The base is the text before the modifier separator")
    func baseText() {
        #expect(GameController.baseText(of: "30") == "30")
        #expect(GameController.baseText(of: "30|-10") == "30")
        #expect(GameController.baseText(of: "20+10|5") == "20+10")
        #expect(GameController.baseText(of: "") == "")
        #expect(GameController.baseText(of: "|5") == "")
    }

    @Test("A separator inside a link or inside parentheses belongs to the base")
    func separatorInsideALinkIsNotASplit() {
        let link = "[Life|Max](RPG://VALUES/0/\(UUID().uuidString)/\(UUID().uuidString))"

        #expect(GameController.baseText(of: link) == link)
        #expect(GameController.baseText(of: "\(link)+10|-4") == "\(link)+10")
        #expect(GameController.baseText(of: "(2|3)|1") == "(2|3)")
    }

    @Test("Base and current resolve as numbers, and a broken modifier leaves the value at its base")
    func numbers() {
        let sut = Self.makeRoot().gameController

        #expect(isClose(sut.gameValueBaseAndCurrent("30"), base: 30, current: 30))
        #expect(isClose(sut.gameValueBaseAndCurrent("30|-10"), base: 30, current: 20))
        #expect(isClose(sut.gameValueBaseAndCurrent("20+10|5"), base: 30, current: 35))
    }

    @Test("A value without a numeric base yields nothing")
    func noNumericBase() {
        let sut = Self.makeRoot().gameController

        #expect(sut.gameValueBaseAndCurrent("") == nil)
        #expect(sut.gameValueBaseAndCurrent("strong") == nil)
        // A formula that does not evaluate, as a trailing operator leaves it.
        #expect(sut.gameValueBaseAndCurrent("20+10+") == nil)
    }

    private static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    private func isClose(_ numbers: (base: Double, current: Double)?, base: Double, current: Double) -> Bool {
        guard let numbers else { return false }
        return abs(numbers.base - base) < 0.0001 && abs(numbers.current - current) < 0.0001
    }
}
#endif
