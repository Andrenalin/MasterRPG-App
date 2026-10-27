// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("QuickLinkScanner")
@MainActor
struct QuickLinkScannerTests {
    private let tableId = UUID()
    private let goblinId = UUID()
    private let wolfId = UUID()
    private let direWolfId = UUID()

    private func candidates(_ entries: [(id: UUID, name: String)]? = nil) -> [LinkEntryModel] {
        QuickLinkScanner.candidates(
            tableId: tableId,
            module: .table,
            entries: entries ?? [(goblinId, "Goblin"), (wolfId, "Wolf"), (direWolfId, "Dire Wolf")]
        )
    }

    private func link(_ name: String, _ entryId: UUID) -> String {
        LinkBuilder.markdown(name: name, module: .table, itemId: tableId, entryId: entryId)
    }

    @Test("Matches whole words case-insensitively")
    func caseInsensitiveWholeWord() {
        let result = QuickLinkScanner.apply(candidates(), to: "A goblin, two Goblins and a hobgoblin.")
        #expect(result.text == "A \(link("Goblin", goblinId)), two Goblins and a hobgoblin.")
        #expect(result.count == 1)
    }

    @Test("Longest name wins on overlap")
    func longestNameWins() {
        let result = QuickLinkScanner.apply(candidates(), to: "Dire Wolf and wolf")
        #expect(result.text == "\(link("Dire Wolf", direWolfId)) and \(link("Wolf", wolfId))")
        #expect(result.count == 2)
    }

    @Test("Names and contents are both replaced, every occurrence")
    func namesAndContents() {
        let result = QuickLinkScanner.apply(candidates(), to: "Goblin\nA Goblin hits a goblin.")
        #expect(result.text == "\(link("Goblin", goblinId))\nA \(link("Goblin", goblinId)) hits a \(link("Goblin", goblinId)).")
        #expect(result.count == 3)
    }

    @Test("Text inside an existing link is left alone")
    func existingLinkSkipped() {
        let existing = "[Goblin](RPG://x/0/\(UUID().uuidString))"
        let result = QuickLinkScanner.apply(candidates(), to: "\(existing) and Goblin")
        #expect(result.text == "\(existing) and \(link("Goblin", goblinId))")
        #expect(result.count == 1)
    }

    @Test("Nothing found leaves the text untouched")
    func noMatch() {
        let result = QuickLinkScanner.apply(candidates(), to: "Nothing here")
        #expect(result == QuickLinkScanner.Result(text: "Nothing here", count: 0))
    }

    @Test("Dice range, empty and duplicate names are no candidates")
    func candidateFiltering() {
        let result = candidates([(UUID(), "1"), (UUID(), "5-10"), (UUID(), "  "), (goblinId, "Goblin"), (UUID(), "goblin")])
        #expect(result.map(\.reference) == ["Goblin"])
    }

    @Test("Markdown emphasis and links are cleaned from the entry name")
    func nameCleaned() {
        let result = candidates([(goblinId, "**Goblin**")])
        #expect(result.map(\.reference) == ["Goblin"])
        #expect(result.first?.markdownUrl == link("Goblin", goblinId))
    }

    @Test("The result parses back to an entry link with the right ids")
    func roundTrip() {
        let result = QuickLinkScanner.apply(candidates(), to: "Goblin")
        let links = LinkReplaceController.links(for: result.text)
        #expect(links.count == 1)
        #expect(links.first?.itemId == tableId)
        #expect(links.first?.entryId == goblinId)
    }
}
