// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// The `RPG://` scheme is a plain three-letter custom scheme any app can also register, so every
/// part of an incoming link is checked and nothing in it can trap or become an id. See
/// CODE_AUDIT §6.5.
@Suite("Deeplink parsing")
struct DeeplinkParsingTests {
    private let itemId = UUID()
    private let entryId = UUID()

    @Test("A well-formed link yields its parts")
    func wellFormedLink() throws {
        let url = try #require(URL(string: "RPG://photo/3/\(itemId.uuidString)/\(entryId.uuidString)/show"))

        #expect(url.isDeeplink)
        #expect(url.linkNumber == 3)
        #expect(url.itemId == itemId)
        #expect(url.childId == entryId)
        #expect(url.commandKey == "show")
    }

    @Test("Only the app scheme is a deeplink, in any case")
    func schemeIsChecked() throws {
        #expect(try #require(URL(string: "rpg://photo/1/\(itemId.uuidString)")).isDeeplink)
        #expect(!(try #require(URL(string: "https://photo/1/\(itemId.uuidString)")).isDeeplink))
        #expect(!(try #require(URL(string: "RPGX://photo/1/\(itemId.uuidString)")).isDeeplink))
        #expect(try #require(URL(string: "https://example.com/a")).moduleIdentifier == .none)
    }

    @Test("Hostile or short paths give no ids and never trap", arguments: [
        "RPG://photo",
        "RPG://photo/",
        "RPG://photo/1",
        "RPG://photo/99999999999999999999999/not-a-uuid",
        "RPG://photo/-1/\u{0}",
        "RPG://photo/1/../../../etc/passwd",
        "RPG://photo/1/%00/%FF"
    ])
    func hostilePaths(link: String) throws {
        let url = try #require(URL(string: link))

        #expect(url.itemId == nil)
        #expect(url.childId == nil)
        // No access traps whatever the path looks like.
        _ = url.linkNumber
        _ = url.commandKey
        _ = url.moduleIdentifier
    }

    @Test("A link number that does not fit an Int is 0")
    func overflowingLinkNumber() throws {
        let url = try #require(URL(string: "RPG://photo/99999999999999999999999/\(itemId.uuidString)"))
        #expect(url.linkNumber == 0)
        #expect(url.itemId == itemId)
    }

    @Test("An unknown module host maps to no module")
    func unknownModule() throws {
        let url = try #require(URL(string: "RPG://unknownmodule/1/\(itemId.uuidString)"))
        #expect(url.moduleIdentifier == .none)
    }
}
