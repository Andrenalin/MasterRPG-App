// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Test case for link removal behavior.
///
/// Provides descriptive names for test output to identify which scenario failed.
struct LinkRemovalTestCase: CustomStringConvertible {
    let input: String
    let expected: String

    var description: String {
        let preview = input.prefix(30)
        let hasMarkdown = input.contains("[") && input.contains("]")
        if hasMarkdown {
            return "remove links from '\(preview)...'"
        } else {
            return "preserve non-link text '\(preview)...'"
        }
    }
}

struct WithoutLinkTests {

    @Test(arguments: [
        LinkRemovalTestCase(input: "Not a Link", expected: "Not a Link"),
        LinkRemovalTestCase(input: "[Not a Link]", expected: "[Not a Link]"),
        LinkRemovalTestCase(input: "[Broken Link](", expected: "[Broken Link]("),
        LinkRemovalTestCase(input: "[Broken Link])", expected: "[Broken Link])"),
        LinkRemovalTestCase(input: "Broken Link](Some)", expected: "Broken Link](Some)"),
        LinkRemovalTestCase(input: "[Easy](Some)", expected: "Easy"),
        LinkRemovalTestCase(input: "[Easy](Some)-[Easy 2](Some)", expected: "Easy-Easy 2"),
        LinkRemovalTestCase(input: "[Hol (sechs)]", expected: "[Hol (sechs)]"),
        LinkRemovalTestCase(input: "[Hol (sechs)](RPG://TABLES/0/558DA4B8-54110398CBF3/220F5D16-)", expected: "Hol (sechs)"),
        LinkRemovalTestCase(input: "[Hol (sechs)](RPG) [Easy](Some)-[Easy 2](Some)", expected: "Hol (sechs) Easy-Easy 2"),
        LinkRemovalTestCase(input: "Hol (sechs)](RPG) [Easy](Some)-[Easy 2](Some)", expected: "Hol (sechs)](RPG) Easy-Easy 2"),
        LinkRemovalTestCase(input: "[Hol (sechs)](RPG) [Easy]Some)-[Easy 2](Some)", expected: "Hol (sechs) [Easy]Some)-Easy 2")
    ])
    func bracketsInsideName(testCase: LinkRemovalTestCase) async throws {
        #expect(testCase.input.withoutLink() == testCase.expected)
    }

    /// CODE_AUDIT_Since_3.0.1 §9.3: `withoutLink()`, `IntentEntityText.readable` and Quick Link
    /// share `LinkBuilder.markdownLinkPattern`.
    @Test("One link pattern for every reader")
    func sharedPattern() {
        // The link is the innermost `[…](…)`, as the old hand-written scan found it.
        #expect("[a [b](x)".withoutLink() == "[a b")
        #expect("`[Orc](RPG://TABLES/0/1)`".withoutLink() == "Orc")
        // A target with a space counts as a link everywhere now.
        #expect(IntentEntityText.readable("[Orc](some target)") == "Orc")
        #expect("[Orc](some target)".withoutLink() == "Orc")
        let linked = QuickLinkScanner.apply([LinkEntryModel(reference: "Orc", markdownUrl: "[Orc](RPG://TABLES/0/1)")], to: "[Orc](some target) and Orc")
        #expect(linked.count == 1)
        #expect(linked.text == "[Orc](some target) and [Orc](RPG://TABLES/0/1)")
    }

    @Test("Ranges are replaced in order, and an overlapping one is skipped")
    func replacingRanges() throws {
        let text = "one two three"
        let one = try #require(text.range(of: "one"))
        let three = try #require(text.range(of: "three"))
        let overlap = try #require(text.range(of: "e tw"))

        #expect(text.replacing(ranges: [(range: three, text: "3"), (range: one, text: "1")]) == "1 two 3")
        #expect(text.replacing(ranges: [(range: one, text: "1"), (range: overlap, text: "X")]) == "1 two three")
        #expect(text.replacing(ranges: []) == text)
    }
}
