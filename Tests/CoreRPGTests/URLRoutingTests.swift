// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

struct URLRoutingTests {
    @Test func gmzExtensionIsCaseInsensitive() throws {
        let url = try #require(URL(string: "file:///tmp/Adventure.GMZ"))

        #expect(url.isGmzDocument)
    }

    @Test func appSchemeAndModuleHostAreCaseInsensitive() throws {
        let url = try #require(URL(string: "RPG://VALUES/1/00000000-0000-0000-0000-000000000001"))

        #expect(url.isDeeplink)
        #expect(url.moduleIdentifier == .value)
        #expect(url.itemId == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    // A bare `itemId/entryId` link (no trailing command) must not read its
    // entry id as a command — this regressed a Table link's auto-expand
    // toggler when embedded in a Character value's content. See
    // CODE_AUDIT_Link.md §9.3 and commit 6fbe6a68.
    @Test func entryLinkWithNoCommandHasNilCommandKey() throws {
        let url = try #require(URL(string: "RPG://TABLE/1/00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000002"))

        #expect(url.childId == UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        #expect(url.commandKey == nil)
    }

    @Test func entryLinkWithCommandReadsCommandFromIndexFour() throws {
        let url = try #require(URL(string: "RPG://TABLE/1/00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000002/show"))

        #expect(url.commandKey == "show")
    }

    // An invalid entry-id segment must still surface a trailing command
    // rather than misreading the invalid segment itself as the command.
    @Test func invalidEntryIdWithCommandReadsCommandFromIndexFour() throws {
        let url = try #require(URL(string: "RPG://TABLE/1/00000000-0000-0000-0000-000000000001/not-a-uuid/show"))

        #expect(url.childId == nil)
        #expect(url.commandKey == "show")
    }

    @Test func itemLinkWithCommandAndNoEntryReadsCommandFromIndexThree() throws {
        let url = try #require(URL(string: "RPG://TABLE/1/00000000-0000-0000-0000-000000000001/show"))

        #expect(url.childId == nil)
        #expect(url.commandKey == "show")
    }
}
#endif
