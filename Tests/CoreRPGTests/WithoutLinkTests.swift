// @copyright André Trettin

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
}
