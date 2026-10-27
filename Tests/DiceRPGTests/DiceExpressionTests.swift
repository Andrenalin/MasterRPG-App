// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_AppIntents3 §4.6: dice notation said to Siri or passed by a shortcut.
@Suite("Dice expressions")
struct DiceExpressionTests {
    @Test("Notation becomes dice and a modifier")
    func notation() throws {
        let roll = try #require(DiceExpression("3d6+2"))
        #expect(roll.terms == [.init(count: 3, sides: 6)])
        #expect(roll.modifier == 2)
        #expect(roll.text == "3d6+2")
        #expect(roll.dieModels.map(\.die.max) == [6, 6, 6])
    }

    @Test("Spoken forms are read", arguments: [
        ("2 W 20", "2d20"),
        ("D20 plus 5", "d20+5"),
        ("d%", "d100"),
        ("1d8 - 1", "d8-1"),
        ("1d6+1d6", "2d6"),
        ("2d6 + 1d8 + 3", "2d6+d8+3"),
        ("1d20 − 2", "d20-2")
    ])
    func spokenForms(input: String, text: String) {
        #expect(DiceExpression(input)?.text == text)
    }

    @Test("Text that is not a roll within the limits is refused", arguments: [
        "", "5", "fireball", "d1", "d1001", "300d6", "0d6", "1d20-1d4", "3d6+"
    ])
    func refused(input: String) {
        #expect(DiceExpression(input) == nil)
    }

    @Test("Spoken values separate dice and rerolls alike")
    func spokenValues() {
        #expect(DiceRollDialog.spokenValues("3|5,2") == "3, 5, 2")
        #expect(DiceRollDialog.spokenValues("17") == "17")
    }

    // CODE_AUDIT_AppIntents3 §5.1: a dialog literal resolved in the app bundle stayed English.
    @Test("An intent reply resolves in the module's catalog")
    func replyResolvesInModuleCatalog() {
        var plain = LocalizedStringResource.intent("Roll Again", bundle: DiceRPG.Resources.bundle)
        plain.locale = Locale(identifier: "de")
        #expect(String(localized: plain) == "Erneut würfeln")

        var formatted = LocalizedStringResource.intent("Rolled \(17)", bundle: DiceRPG.Resources.bundle)
        formatted.locale = Locale(identifier: "de")
        #expect(String(localized: formatted) == "17 gewürfelt")
    }
}
