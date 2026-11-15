// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §10.10: table-driven checks of the entry text parser and the sheet row state.
@Suite("Entry text parser")
struct EntryTextParserTableTests {
    struct Case: CustomTestStringConvertible {
        let label: String
        let input: String
        let expected: String
        var testDescription: String { label }
    }

    static let removeLineBreakCases = [
        Case(label: "wrapped lines join with one space", input: "Title\nfirst line\nsecond line", expected: "Title\nfirst line second line"),
        Case(label: "no trailing space at the paragraph end", input: "Title\nfirst line \n", expected: "Title\nfirst line"),
        Case(label: "a hyphen before a lowercase continuation joins the word", input: "Title\nre-\nsolved", expected: "Title\nresolved"),
        Case(label: "a hyphen before a capital stays", input: "Title\nwell-\nKnown", expected: "Title\nwell- Known"),
        Case(label: "a hyphen before a digit stays", input: "Title\nroll-\n20", expected: "Title\nroll- 20"),
        Case(label: "paragraphs stay separated", input: "A\none\ntwo\n\nB\nthree", expected: "A\none two\n\nB\nthree"),
        Case(label: "carriage returns are line breaks", input: "A\r\none\r\ntwo", expected: "A\none two"),
        Case(label: "a title without content stays alone", input: "Only a title", expected: "Only a title")
    ]

    @Test("removeLineBreaks", arguments: removeLineBreakCases)
    func removeLineBreaks(_ testCase: Case) {
        #expect(EntryTextParser().removeLineBreaks(from: testCase.input) == testCase.expected)
    }

    @Test("parse splits on empty lines and trims names and content")
    func parseSplitsBlocks() {
        let parsed = EntryTextParser().parse("  A  \none\ntwo\n\nB\n\n\nC\nthree\n")

        #expect(parsed.map(\.name) == ["A", "B", "C"])
        #expect(parsed.map(\.content) == ["one\ntwo", "", "three"])
    }

    @Test("format and parse round-trip")
    func formatParseRoundTrip() {
        let entries = [(name: "A", content: "one"), (name: "B", content: ""), (name: "C", content: "x\ny")]

        let parsed = EntryTextParser().parse(EntryTextParser().format(entries))

        #expect(parsed.map(\.name) == entries.map(\.name))
        #expect(parsed.map(\.content) == entries.map(\.content))
    }

    @Test("transformingContent leaves titles and empty lines alone")
    func transformKeepsTitles() {
        let result = EntryTextParser().transformingContent(of: "Title\nbody\n\nNext\nmore") { $0.uppercased() }

        #expect(result == "Title\nBODY\n\nNext\nMORE")
    }
}

@MainActor
@Suite("Sheet row state")
struct SheetRowStateTests {
    private func row(isShown: Bool) -> SheetModel {
        SheetModel(
            source: ItemRowModel(itemId: UUID(), typeId: .table),
            isShown: isShown,
            name: "Goblin",
            description: "",
            entries: []
        )
    }

    @Test("A new row remembers its expanded state", arguments: [true, false])
    func newRowRemembersExpandedState(isShown: Bool) {
        #expect(row(isShown: isShown).lastIsShown == isShown)
    }

    @Test("Clearing a search restores the expanded state a row had when it was created")
    func clearingSearchRestoresState() {
        let model = row(isShown: true)

        _ = model.filter(searchText: "no match anywhere")
        _ = model.filter(searchText: "", shouldRestoreState: true)

        #expect(model.isShown)
        #expect(model.isHidden == false)
    }

    @Test("A row that does not match a search is hidden")
    func nonMatchingRowIsHidden() {
        let model = row(isShown: true)

        #expect(model.filter(searchText: "zzz") == false)
        #expect(model.filter(searchText: "gob"))
    }
}
