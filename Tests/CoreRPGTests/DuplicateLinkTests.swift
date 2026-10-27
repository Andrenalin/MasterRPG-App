// @copyright André Trettin

@testable import CoreRPG
import Foundation
import Testing

/// The same link appearing more than once in one text (typical for the quick editor, where all
/// entries share one text and the quick linker writes every link as number 0): only the first
/// occurrence became an attributed link, the others stayed plain markdown.
@Suite("Duplicate links in one text")
@MainActor
struct DuplicateLinkTests {
    private let tableId = UUID.fixture1
    private let entryId = UUID.fixture2
    private let otherEntryId = UUID.fixture3

    private func link(_ name: String, number: Int = 0, entry: UUID? = nil, command: String? = nil) -> String {
        LinkBuilder.markdown(name: name, module: .table, linkNumber: number, itemId: tableId, entryId: entry ?? entryId, command: command)
    }

    private func model(for text: String) -> TextEditModel {
        let model = TextEditModel(linkRegisterController: LinkRegisterController(root: nil))
        model.reset(text: text, source: ItemRowModel(itemId: .fixture4, typeId: .adventure))
        return model
    }

    private func linkRuns(in model: TextEditModel) -> [String] {
        model.attributedText.runs.compactMap { run in
            run.linkContent == nil ? nil : String(model.attributedText[run.range].characters)
        }
    }

    // MARK: - TextEditModel

    @Test("Every occurrence of the same link becomes an attributed link")
    func sameLinkTwice() {
        let model = model(for: "Entry 1\n\(link("Goblin"))\n\nEntry 2\n\(link("Goblin"))")

        #expect(String(model.attributedText.characters) == "Entry 1\nGoblin\n\nEntry 2\nGoblin")
        #expect(linkRuns(in: model) == ["Goblin", "Goblin"])
    }

    @Test("Three occurrences, mixed with another entry link")
    func sameLinkThreeTimes() {
        let model = model(for: "\(link("Goblin")) \(link("Orc", entry: otherEntryId)) \(link("Goblin")) \(link("Goblin"))")

        #expect(String(model.attributedText.characters) == "Goblin Orc Goblin Goblin")
        #expect(linkRuns(in: model) == ["Goblin", "Orc", "Goblin", "Goblin"])
    }

    @Test("Identical command links are all attributed")
    func sameCommandLinkTwice() {
        let model = model(for: "\(link("Show", number: 600, command: "show")) and \(link("Show", number: 600, command: "show"))")

        #expect(String(model.attributedText.characters) == "Show and Show")
        #expect(linkRuns(in: model) == ["Show", "Show"])
    }

    @Test("Converting back to text numbers each occurrence")
    func roundTripNumbersOccurrences() {
        let model = model(for: "\(link("Goblin")) \(link("Goblin")) \(link("Goblin"))")
        model.resetText()

        #expect(model.text == "\(link("Goblin", number: 0)) \(link("Goblin", number: 1)) \(link("Goblin", number: 2))")
    }

    @Test("Already numbered links still work")
    func alreadyNumbered() {
        let model = model(for: "\(link("Goblin", number: 0)) \(link("Goblin", number: 1))")

        #expect(linkRuns(in: model) == ["Goblin", "Goblin"])
    }

    // MARK: - LinkReplaceController

    @Test("Each link reports the range of its own occurrence")
    func rangesAreOccurrenceAware() throws {
        let text = "\(link("Goblin")) / \(link("Goblin")) / \(link("Goblin"))"
        let links = LinkReplaceController.links(for: text).sorted { $0.range.lowerBound < $1.range.lowerBound }

        try #require(links.count == 3)
        #expect(Set(links.map(\.range)).count == 3)
        for found in links {
            #expect(text[found.range] == link("Goblin"))
        }
        #expect(links.map(\.linkNumber) == [0, 1, 2])
    }

    @Test("Repairing three identical links numbers them 0, 1, 2")
    func repairThreeDuplicates() {
        var text = "\(link("Goblin")) \(link("Goblin")) \(link("Goblin"))"
        let links = LinkReplaceController.linksRepair(for: &text)

        #expect(text == "\(link("Goblin", number: 0)) \(link("Goblin", number: 1)) \(link("Goblin", number: 2))")
        for found in links {
            #expect(text[found.range] == found.markDown)
        }
        #expect(Set(links.map(\.range)).count == 3)
    }
}
