// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Foundry presentation helpers")
struct FoundryPresentationHelpersTests {
    @Test("HTML entities and control characters become safe visible text")
    func decodesHTMLAndControls() {
        // Given
        let html = """
        <p>R&uuml;stung&nbsp;&amp; Schutz&#x3A;<br>Zeile&#10;Zwei &#128;</p>
        <script>privateLeak()</script>\u{0000}\u{0007}
        """

        // When
        let result = FoundryTextDecoder.plainText(fromHTML: html)

        // Then
        #expect(result == "Rüstung & Schutz:\nZeile\nZwei €")
        #expect(!result.contains("privateLeak"))
        #expect(result.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x0A || scalar.value >= 0x20
        })
    }

    /// CODE_AUDIT_26 §7.4: the linear scanner removes what the former patterns removed.
    @Test(
        "Comments and script-like blocks are removed, unterminated openers stay",
        arguments: [
            ("a<!-- hidden -->b", "ab"),
            ("a<!---->b", "ab"),
            ("a<SCRIPT type=x>leak()</ script >b", "ab"),
            ("a< style >p{}</STYLE>b<template>x</template>c<noscript>y</noscript>d", "abcd"),
            ("a<scripts>keep</scripts>b", "akeepb"),
            ("a<script>no closer", "ano closer"),
            ("a<!-- no closer", "a<!-- no closer"),
            ("a<script>x</style>b", "axb"),
        ]
    )
    func removesInvisibleBlocks(input: String, expected: String) {
        #expect(FoundryTextDecoder.plainText(fromHTML: input) == expected)
    }

    @Test("Many unterminated openers and ampersands finish quickly")
    func unterminatedOpenersAreLinear() {
        let openers = String(repeating: "<!--", count: 50_000) + String(repeating: "<script>", count: 50_000)
        let ampersands = String(repeating: "&", count: 200_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = FoundryTextDecoder.plainText(fromHTML: openers)
            _ = FoundryTextDecoder.decodedText(ampersands)
        }
        // Generous on purpose: this guards against quadratic scanning (minutes at this size), not
        // against a slow runner. It takes ~1 s alone and measured 10.6 s under a loaded full run.
        #expect(elapsed < .seconds(30))
    }

    // CODE_AUDIT_28 §6.3: the generic tag patterns scanned to the end for every `<` without a `>`.
    @Test("A long run of unterminated tags finishes quickly")
    func unterminatedTagsAreLinear() {
        let run = String(repeating: "<a", count: 60_000)
        let clock = ContinuousClock()
        var result = ""
        let elapsed = clock.measure {
            result = FoundryTextDecoder.plainText(fromHTML: run + " tail")
        }
        // Quadratic scanning takes minutes here; the bound only has to survive a loaded runner.
        #expect(elapsed < .seconds(30))
        #expect(result.hasSuffix("tail"))
    }

    @Test(
        "Tags become text, line breaks and paragraph breaks",
        arguments: [
            ("a<br>b", "a\nb"),
            ("a<BR/>b", "a\nb"),
            ("a< hr >b", "a\nb"),
            ("<p>a</p><p>b</p>", "a\n\nb"),
            ("x<b>bold</b>y", "xboldy"),
            ("<a href=\"u\">link</a>", "link"),
            ("1 < 2 and 3 > 2", "1 < 2 and 3 > 2"),
            ("a<brx>b", "ab"),
        ]
    )
    func stripsTags(input: String, expected: String) {
        #expect(FoundryTextDecoder.plainText(fromHTML: input) == expected)
    }

    @Test(
        "Entity decoding handles named, decimal, hexadecimal, and unknown entities",
        arguments: [
            ("Shield &amp; ward", "Shield & ward"),
            ("It&#39;s ready", "It's ready"),
            ("Roll &#x1F3B2;", "Roll 🎲"),
            ("A&#13;&#10;B&Tab;C", "A\nB C"),
            ("Keep &systemSpecific;", "Keep &systemSpecific;"),
        ]
    )
    func decodesEntity(input: String, expected: String) {
        // When
        let result = FoundryTextDecoder.decodedText(input)

        // Then
        #expect(result == expected)
    }

    @Test("Nested JSON becomes deterministic editable groups")
    func groupsNestedJSONValues() throws {
        // Given
        let source: FoundryJSONValue = .object([
            "attributes": .object([
                "body": .object([
                    "base": .integer(5),
                    "label": .string("Strong")
                ])
            ]),
            "inventory": .array([
                .string("Sword"),
                .string("Shield")
            ])
        ])

        // When
        let nodes = FoundryValueHierarchy.nodes(from: source)

        // Then
        let attributes = try #require(nodes.first)
        let body = try #require(attributes.children.first)
        let base = try #require(body.children.first)
        #expect(nodes.map(\.component) == ["attributes", "inventory"])
        #expect(attributes.path == "attributes")
        #expect(body.component == "body")
        #expect(body.path == "attributes.body")
        #expect(body.children.map(\.component) == ["base", "label"])
        #expect(base.path == "attributes.body.base")
        #expect(base.value == .integer(5))
        #expect(attributes.valueCount == 2)
        #expect(nodes[1].children.map(\.component) == ["0", "1"])
    }

    @Test("Dotted values share groups and retain a value on a group node")
    func groupsDottedValues() throws {
        // Given
        let values = [
            FoundryRuleValue(path: "attributes.body.base", value: .integer(5)),
            FoundryRuleValue(path: "attributes.body", value: .string("Body")),
            FoundryRuleValue(path: "attributes.mind.base", value: .integer(3)),
            FoundryRuleValue(path: "inventory.10", value: .string("Potion")),
            FoundryRuleValue(path: "inventory.2", value: .string("Shield")),
        ]

        // When
        let nodes = FoundryValueHierarchy.nodes(from: values)

        // Then
        let attributes = try #require(nodes.first)
        let body = try #require(attributes.children.first)
        #expect(nodes.map(\.component) == ["attributes", "inventory"])
        #expect(attributes.children.map(\.component) == ["body", "mind"])
        #expect(body.value == .string("Body"))
        #expect(body.children.map(\.component) == ["base"])
        #expect(body.children.first?.value == .integer(5))
        #expect(attributes.valueCount == 3)
        #expect(nodes[1].children.map(\.component) == ["2", "10"])
    }

    // CODE_AUDIT_28 §6.4
    @Test("A key of a hundred thousand dots stays one literal component")
    func overLongPathIsOneComponent() {
        let path = String(repeating: "a.", count: 100_000) + "a"
        let values = [
            FoundryRuleValue(path: path, value: .integer(1)),
            FoundryRuleValue(path: "attributes.body", value: .integer(2)),
        ]

        let nodes = FoundryValueHierarchy.nodes(from: values)

        #expect(nodes.count == 2)
        let long = nodes.first { $0.component == path }
        #expect(long?.value == .integer(1))
        #expect(long?.children.isEmpty == true)
        #expect(nodes.first { $0.component == "attributes" }?.children.first?.component == "body")
    }
}
