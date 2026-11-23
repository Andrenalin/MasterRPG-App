// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_19 §9.18: one parser now handles the four link shapes.
@Suite("Reference scanner")
struct ReferenceScannerTests {
    private let table = UUID()
    private let entry = UUID()

    @Test("All four link shapes are found, with their commands")
    func fourShapes() {
        let text = """
            [A](rpg://TABLE/1/\(table)) \
            [B](rpg://TABLE/2/\(table)/Roll) \
            [C](rpg://TABLE/3/\(table)/\(entry)) \
            [D](rpg://TABLE/4/\(table)/\(entry)/Roll)
            """

        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: text)

        #expect(links.tables.map(\.name).sorted() == ["A", "B"])
        #expect(links.tables.first { $0.name == "B" }?.command == "Roll")
        #expect(links.tables.first { $0.name == "A" }?.command == nil)
        #expect(links.tableEntries.map(\.name).sorted() == ["C", "D"])
        #expect(links.tableEntries.allSatisfy { $0.table == table && $0.entry == entry })
        #expect(links.tableEntries.first { $0.name == "D" }?.command == "Roll")
    }

    @Test("A command link is not mistaken for an entry link")
    func commandIsNotAnEntry() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[B](rpg://TABLE/2/\(table)/Roll)")
        #expect(links.tableEntries.isEmpty)
        #expect(links.tables.count == 1)
    }

    @Test("A link whose table is not a UUID is ignored")
    func invalidTableIsIgnored() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[X](rpg://TABLE/1/not-a-uuid)")
        #expect(links.tables.isEmpty)
    }

    // MARK: - CODE_AUDIT_TestGaps §5.15

    @Test("Text without the scheme, and an empty text, have no links")
    func noSchemeNoLinks() {
        #expect(ReferenceScanner.allUuidUrls(for: "rpg", in: "").tables.isEmpty)
        let plain = ReferenceScanner.allUuidUrls(for: "rpg", in: "just text, [a](https://example.com/\(table))")
        #expect(plain.tables.isEmpty && plain.tableEntries.isEmpty)
    }

    @Test("Only links of the asked scheme are found")
    func schemeIsExact() {
        let text = "[A](rpg://TABLE/1/\(table)) [B](other://TABLE/1/\(table))"

        #expect(ReferenceScanner.allUuidUrls(for: "rpg", in: text).tables.map(\.name) == ["A"])
        #expect(ReferenceScanner.allUuidUrls(for: "other", in: text).tables.map(\.name) == ["B"])
        #expect(ReferenceScanner.allUuidUrls(for: "rp", in: text).tables.isEmpty, "a prefix of the scheme is another scheme")
    }

    @Test("The module, link number, table and entry are returned as written")
    func fieldsAreReturned() throws {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[Goblin](rpg://VALUE/42/\(table)/\(entry))")

        let link = try #require(links.tableEntries.first)
        #expect(link.name == "Goblin")
        #expect(link.module == "VALUE")
        #expect(link.linkNumber == "42")
        #expect(link.table == table)
        #expect(link.entry == entry)
        #expect(link.command == nil)
        #expect(links.tables.isEmpty)
    }

    @Test("Several links in one text are all found, in any order of shapes")
    func severalLinks() {
        let other = UUID()
        let text = """
            Start [One](rpg://TABLE/1/\(table)) then [Two](rpg://TABLE/2/\(other)) and
            [Three](rpg://TABLE/3/\(table)/\(entry)) end.
            """

        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: text)

        #expect(Set(links.tables.map(\.table)) == [table, other])
        #expect(links.tableEntries.map(\.name) == ["Three"])
    }

    @Test("A link whose entry is not a UUID is ignored as an entry")
    func invalidEntryIsIgnored() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[X](rpg://TABLE/1/\(table)/not-a-uuid)")

        #expect(links.tableEntries.isEmpty)
    }

    @Test("A link with an empty name is still a link")
    func emptyName() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[](rpg://TABLE/1/\(table))")

        #expect(links.tables.count == 1)
        #expect(links.tables.first?.name == "")
    }

    @Test("A broken link next to a good one does not hide the good one")
    func brokenNeighbour() {
        let text = "[Bad](rpg://TABLE/x/\(table)) [Good](rpg://TABLE/1/\(table))"

        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: text)

        #expect(links.tables.map(\.name) == ["Good"], "a link number must be digits")
    }

    // CODE_AUDIT_28 §7.14: every `[` without a closing `]` scanned to the end of the text.
    @Test("Long runs of unterminated link labels are scanned in linear time")
    func unterminatedLabelsAreLinear() {
        let text = String(repeating: "[a", count: 40_000) + " RPG://"
        let clock = ContinuousClock()
        var result = false
        let elapsed = clock.measure {
            result = ReferenceScanner.allUuidUrls(for: "RPG", in: text).tables.isEmpty
            _ = text.withoutLink()
        }
        #expect(result)
        #expect(elapsed < .seconds(2))
    }
}
