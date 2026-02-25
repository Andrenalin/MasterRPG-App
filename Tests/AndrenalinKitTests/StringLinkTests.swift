// @copyright André Trettin

import Testing

@testable import CoreRPG

/// Test case for link toggle behavior.
///
/// Provides descriptive names for test output to identify which scenario failed.
struct LinkToggleTestCase: CustomStringConvertible {
    let input: String
    let url: String
    let insertText: String
    let expected: String

    var description: String {
        let preview = input.prefix(30)
        let hasLink = input.contains(url)
        return hasLink ? "remove link from '\(preview)...'" : "add link to '\(preview)...'"
    }
}

struct StringLinkTests {

    @Test(arguments: [
        LinkToggleTestCase(
            input: "Hi Text",
            url: "[Name](RPG://TABLES/0/558DA4B8-54110398CBF3)",
            insertText: "Inserted",
            expected: "Hi Text"
        ),
        LinkToggleTestCase(
            input: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)",
            url: "[Name](RPG://TABLES/0/558DA4B8-54110398CBF3)",
            insertText: "Inserted",
            expected: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)➡️Inserted⬅️"
        ),
        LinkToggleTestCase(
            input: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)➡️Inserted⬅️",
            url: "[Name](RPG://TABLES/0/558DA4B8-54110398CBF3)",
            insertText: "Inserted",
            expected: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)"
        ),
        LinkToggleTestCase(
            input: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3) more Text",
            url: "[Name](RPG://TABLES/0/558DA4B8-54110398CBF3)",
            insertText: "Inserted",
            expected: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)➡️Inserted⬅️ more Text"
        ),
        LinkToggleTestCase(
            input: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)➡️Insert [Name](RPG://TABLES/0/558DA4B8-54110398CBF2)⬅️",
            url: "[Name](RPG://TABLES/0/558DA4B8-54110398CBF2)",
            insertText: "Inner",
            expected: "Hi [Name](RPG://TABLES/0/558DA4B8-54110398CBF3)➡️Insert [Name](RPG://TABLES/0/558DA4B8-54110398CBF2)➡️Inner⬅️⬅️"
        )
    ])
    func bracketsInsideName(testCase: LinkToggleTestCase) async throws {
        // Act
        let result = testCase.input.toggleLink(url: testCase.url, with: testCase.insertText)

        // Assert
        #expect(result == testCase.expected)
    }

    @Test("Toggle link with three existing links")
    func handle3Links() {
        // Arrange
        let text = "**Battelvalue**: [Strength](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/16587A5F-327B-4579-B528-D84E9E8DA363)+[Dexterity](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/ACAB03A0-A174-4A52-B818-9E6E8344AEC0)+[Intelligence](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/4FC4ABB3-97FE-417D-A89A-4D845126D030)➡️ [Show](RPG://VALUES/600/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/4FC4ABB3-97FE-417D-A89A-4D845126D030/show) 12⬅️*2 = 42"

        let url = "[Dexterity](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/ACAB03A0-A174-4A52-B818-9E6E8344AEC0)"

        // Act
        let result = text.toggleLink(url: url, with: "[Show](RPG://VALUES/600/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/ACAB03A0-A174-4A52-B818-9E6E8344AEC0/show) 14")

        // Assert
        let expected = "**Battelvalue**: [Strength](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/16587A5F-327B-4579-B528-D84E9E8DA363)+[Dexterity](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/ACAB03A0-A174-4A52-B818-9E6E8344AEC0)➡️[Show](RPG://VALUES/600/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/ACAB03A0-A174-4A52-B818-9E6E8344AEC0/show) 14⬅️+[Intelligence](RPG://VALUES/0/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/4FC4ABB3-97FE-417D-A89A-4D845126D030)➡️ [Show](RPG://VALUES/600/B6B05571-E7E7-4BAE-B3F1-E503580DCB58/4FC4ABB3-97FE-417D-A89A-4D845126D030/show) 12⬅️*2 = 42"

        #expect(result == expected)
    }
}
