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

    /// CODE_AUDIT_Since_3.0.1 §7.1: the excerpt ran `readable` over each whole entry.
    @Test("A readable prefix of a long text matches the readable text, cut to the length")
    func readablePrefixOfLongText() {
        let link = "[Goblin](RPG://CHARACTERS/0/\(UUID().uuidString))"
        let chapter = String(repeating: "The \(link) waits in the **dark** cave. ", count: 5_000)

        let prefix = IntentEntityText.readablePrefix(chapter, length: 100)

        #expect(prefix == String(IntentEntityText.readable(chapter).prefix(100)))
        #expect(prefix.count == 100)
    }

    @Test("Short text is read whole, and a zero length gives nothing")
    func readablePrefixOfShortText() {
        #expect(IntentEntityText.readablePrefix("  [Orc](RPG://CHARACTERS/0/1) ", length: 50) == "Orc")
        #expect(IntentEntityText.readablePrefix("Orc", length: 0) == "")
        #expect(IntentEntityText.readablePrefix("Orc and goblin", length: 3) == "Orc")
    }

    @Test("A link the scan cuts into is left out, never its target")
    func readablePrefixDropsCutLink() {
        let link = "[x](RPG://CHARACTERS/0/\(UUID().uuidString)) "
        let text = String(repeating: link, count: 100)

        let prefix = IntentEntityText.readablePrefix(text, length: 10)

        #expect(!prefix.contains("RPG://"))
        #expect(!prefix.contains("]("))
    }
}
