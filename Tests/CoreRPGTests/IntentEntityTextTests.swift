// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_AppIntents3 §4.3, §4.15: the text Siri reads and the Markdown intents store.
@Suite("Intent text")
struct IntentEntityTextTests {
    @Test("Links become their labels and bold markers are dropped")
    func readable() {
        let id = UUID().uuidString
        #expect(IntentEntityText.readable("[Goblin](RPG://CHARACTERS/0/\(id)) attacks **now**") == "Goblin attacks now")
        #expect(IntentEntityText.readable("  plain text \n") == "plain text")
    }

    @Test("No text gives an empty string")
    func emptyMarkdown() {
        #expect(intentMarkdown(from: nil) == "")
    }

    @Test("Inline formatting is kept as Markdown")
    func inlineMarkdown() throws {
        let text = try AttributedString(markdown: "**Hook:** a *dark* tale, see [the map](https://example.com/map)")
        #expect(intentMarkdown(from: text) == "**Hook:** a *dark* tale, see [the map](https://example.com/map)")
    }

    @Test("Headings, lists and paragraphs are kept as blocks")
    func blockMarkdown() throws {
        let source = "# Tavern\n\nA smoky room.\n\n- Barkeep\n- Bard\n\n1. Enter\n2. Order"
        let text = try AttributedString(markdown: source)
        #expect(intentMarkdown(from: text) == source)
    }

    @Test("Plain text passes through")
    func plainText() {
        #expect(intentMarkdown(from: AttributedString("Just a note.")) == "Just a note.")
    }
}
