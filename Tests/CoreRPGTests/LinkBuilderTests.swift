// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_15 §9.15: one place spells out the link grammar.
@Suite("LinkBuilder")
struct LinkBuilderTests {
    private let itemId = UUID()
    private let entryId = UUID()

    @Test("Item address")
    func itemAddress() {
        let address = LinkBuilder.address(module: .photo, linkNumber: 3, itemId: itemId)
        #expect(address == "\(URL.appScheme)://\(NetworkModules.photo.token)/3/\(itemId.uuidString)")
    }

    @Test("Entry and command segments are appended in order")
    func entryAndCommand() {
        let address = LinkBuilder.address(module: .dice, itemId: itemId, entryId: entryId, command: "roll")
        #expect(address == "\(URL.appScheme)://\(NetworkModules.dice.token)/0/\(itemId.uuidString)/\(entryId.uuidString)/roll")
    }

    @Test("Markdown wraps the name around the address")
    func markdown() {
        let link = LinkBuilder.markdown(name: "Goblin", module: .value, itemId: itemId)
        #expect(link == "[Goblin](\(LinkBuilder.address(module: .value, itemId: itemId)))")
    }
}
