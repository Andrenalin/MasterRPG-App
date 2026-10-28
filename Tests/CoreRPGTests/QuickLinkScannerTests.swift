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

    @Test("Plain apply replaces every occurrence of the text it is given")
    func namesAndContents() {
        let result = QuickLinkScanner.apply(candidates(), to: "Goblin\nA Goblin hits a goblin.")
        #expect(result.text == "\(link("Goblin", goblinId))\nA \(link("Goblin", goblinId)) hits a \(link("Goblin", goblinId)).")
        #expect(result.count == 3)
    }

    // MARK: Entry text (CODE_AUDIT_Since_3.0.1 §5.1)

    @Test("In an entry text only the content is linked, every title stays as it is")
    func contentOnly() {
        let text = "Goblin Den\nA Goblin hides.\n\nWolf Pit\nTwo wolves and a Wolf."
        let result = QuickLinkScanner.applyToContent(candidates(), to: text)
        #expect(result.text == "Goblin Den\nA \(link("Goblin", goblinId)) hides.\n\nWolf Pit\nTwo wolves and a \(link("Wolf", wolfId)).")
        #expect(result.count == 2)
    }

    @Test("A title that is exactly a candidate name is not linked")
    func titleEqualToCandidate() {
        let result = QuickLinkScanner.applyToContent(candidates(), to: "Goblin\nThe goblin.")
        #expect(result.text == "Goblin\nThe \(link("Goblin", goblinId)).")
    }

    @Test(
        "The parsed entry names never change",
        arguments: [
            "Goblin Den\nA Goblin hides.\n\nWolf Pit\nA wolf.",
            "   \nGoblin\ngoblin attacks",
            "\n\nDire Wolf\n\nWolf\nThe Dire Wolf howls.",
            "Goblin\r\nA goblin.\r\n\r\nWolf\r\nA wolf.",
            "Goblin"
        ]
    )
    func parsedNamesUnchanged(text: String) {
        let parser = EntryTextParser()
        let result = QuickLinkScanner.applyToContent(candidates(), to: text)
        #expect(parser.parse(result.text).map(\.name) == parser.parse(text).map(\.name))
    }

    @Test("Without a match the text is returned untouched, line endings included")
    func contentOnlyNoMatch() {
        let text = "Goblin\r\nNothing here."
        #expect(QuickLinkScanner.applyToContent(candidates(), to: text) == QuickLinkScanner.Result(text: text, count: 0))
    }

    // MARK: Scan outcome

    private var monsters: FakeItemModel {
        FakeItemModel(id: tableId, name: "Monsters", entries: [FakeEntryModel(id: goblinId, name: "Goblin", content: "")])
    }

    @Test("Choosing the table being edited is ignored and reported, the text is not scanned")
    func sameTableIgnored() {
        let outcome = QuickLinkScanner.scan(monsters, editedItemId: tableId, text: "Goblin\nA goblin.")
        #expect(outcome == .sameTable)
    }

    @Test("Another table is scanned in the content")
    func otherTableScanned() {
        let outcome = QuickLinkScanner.scan(monsters, editedItemId: UUID(), text: "Cave\nA goblin.")
        let linked = FakeItemModel.typeId
        #expect(outcome == .linked(QuickLinkScanner.Result(
            text: "Cave\nA \(LinkBuilder.markdown(name: "Goblin", module: linked, itemId: tableId, entryId: goblinId)).",
            count: 1
        )))
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
