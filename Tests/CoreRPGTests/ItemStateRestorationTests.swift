// @copyright André Trettin

@testable import CoreRPG
import Foundation
import Testing

@Suite("Item state restoration")
struct ItemStateRestorationTests {
    @Test("The stored item is restored while nothing is selected")
    func restoresWhenNothingSelected() {
        #expect(ItemStateRestoration.itemToRestore(stored: .fixture1, current: nil) == .fixture1)
    }

    @Test("A selection made during the delay is kept, with or without a stored item")
    func keepsSelectionMadeMeanwhile() {
        #expect(ItemStateRestoration.itemToRestore(stored: nil, current: .fixture2) == nil)
        #expect(ItemStateRestoration.itemToRestore(stored: .fixture1, current: .fixture2) == nil)
    }

    @Test("Nothing stored and nothing selected restores nothing")
    func nothingToRestore() {
        #expect(ItemStateRestoration.itemToRestore(stored: nil, current: nil) == nil)
    }
}
