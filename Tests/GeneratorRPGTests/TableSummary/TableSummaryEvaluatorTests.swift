// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The scoring rules and the fixtures themselves. These need no Apple Intelligence and run in
/// every test run, so a broken evaluation is found before it judges the model.
@Suite("Table summary evaluator")
struct TableSummaryEvaluatorTests {
    private let evaluator = TableSummaryEvaluator()
    private let expectation = TableSummaryExpectation(
        tags: PdfTagExpectation(
            conceptGroups: [["forest", "woods"], ["encounter"], ["fantasy", "monster"]],
            minimumMatchedGroups: 2
        ),
        titleConcepts: [["forest", "woods"]],
        descriptionConcepts: [["encounter", "creature"]],
        forbiddenTerms: ["Wald"]
    )

    private let goodTitle = "Forest Encounters"
    private let goodDescription = "Random creatures and travelers the party meets in the forest. Roll once per watch."
    private let goodTags = ["Encounter", "Forest", "Fantasy", "Wilderness"]

    private func evaluate(
        title: String? = nil,
        description: String? = nil,
        tags: [String]? = nil
    ) -> TableSummaryVerdict {
        evaluator.evaluate(
            title: title ?? goodTitle,
            description: description ?? goodDescription,
            tags: tags ?? goodTags,
            expectation: expectation
        )
    }

    @Test("A good summary passes")
    func goodSummary() {
        let result = evaluate()

        #expect(result.passed)
        #expect(result.violations.isEmpty)
        #expect(result.conceptScore == 1)
    }

    // MARK: - Title

    @Test("An empty title fails")
    func emptyTitle() {
        #expect(evaluate(title: "  ").titleRuleViolations == ["is empty"])
    }

    @Test("A title that is too long fails", arguments: [
        "The Very Long Forest Encounters Table For Every Single Party",
        "Encounters in the dark forest near the old road at dusk"
    ])
    func longTitle(title: String) {
        #expect(!evaluate(title: title).titleRuleViolations.isEmpty)
    }

    @Test("A generic title or a label form fails", arguments: [
        "Table", "Random Table", "Tabelle", "Table: Forest", "Zufallstabelle: Wald", "RPG Loot Table: Random Treasure", "RPG-Tabelle: Rätsel und Hinweise"
    ])
    func genericTitle(title: String) {
        let result = evaluate(title: title)

        #expect(result.titleRuleViolations.contains { $0.contains("generic") })
    }

    @Test("A title that reads like a sentence fails")
    func sentenceTitle() {
        #expect(evaluate(title: "Forest encounters for the party.").titleRuleViolations.contains("reads like a sentence"))
    }

    @Test("A title without any expected concept fails")
    func titleWithoutConcept() {
        let result = evaluate(title: "Roadside Surprises")

        #expect(result.titleRuleViolations.isEmpty)
        #expect(result.conceptViolations.contains { $0.hasPrefix("title matches none") })
        #expect(!result.passed)
    }

    // MARK: - Description

    @Test("An empty description fails")
    func emptyDescription() {
        #expect(evaluate(description: "").descriptionRuleViolations == ["is empty"])
    }

    @Test("A description with three sentences fails")
    func threeSentences() {
        let result = evaluate(description: "The party meets creatures. Bandits may rob them. Roll again for a second encounter.")

        #expect(result.descriptionRuleViolations.contains { $0.contains("3 sentences") })
    }

    @Test("A description with a decimal or dice notation stays one sentence")
    func decimalIsNotASentence() {
        #expect(TableSummaryEvaluator.sentenceCount(in: "Roll 1d8 for the encounter, 2.5 miles into the forest.") == 1)
    }

    @Test("A very short or very long description fails")
    func descriptionLength() {
        #expect(evaluate(description: "Encounters.").descriptionRuleViolations.contains { $0.contains("shorter") })
        let long = String(repeating: "encounter ", count: 40)
        #expect(evaluate(description: long).descriptionRuleViolations.contains { $0.contains("longer") })
    }

    @Test("A description that repeats the title fails")
    func descriptionRepeatsTitle() {
        let result = evaluate(title: "Forest encounters on the road", description: "Forest Encounters on the road")

        #expect(result.descriptionRuleViolations.contains("repeats the title"))
    }

    @Test("A description without any expected concept fails")
    func descriptionWithoutConcept() {
        let result = evaluate(description: "A list of things that can happen on a journey through the trees.")

        #expect(result.descriptionRuleViolations.isEmpty)
        #expect(result.conceptViolations.contains { $0.hasPrefix("description matches none") })
    }

    // MARK: - Tags

    @Test("Tag count must be 3 to 5", arguments: [
        (["Forest", "Encounter"], false),
        (["Forest", "Encounter", "Fantasy"], true),
        (["Forest", "Encounter", "Fantasy", "Wolves", "Bandits"], true),
        (["Forest", "Encounter", "Fantasy", "Wolves", "Bandits", "Traps"], false)
    ])
    func tagCount(tags: [String], passes: Bool) {
        #expect(evaluate(tags: tags).tagRuleViolations.isEmpty == passes)
    }

    @Test("Table-form tags are generic", arguments: ["Table", "Random Table", "Entries", "Tabelle", "Einträge"])
    func genericTableTag(tag: String) {
        let result = evaluate(tags: ["Forest", "Encounter", tag])

        #expect(result.tagRuleViolations.contains { $0.contains("generic") })
    }

    @Test("A tag that repeats the title fails")
    func tagRepeatsTitle() {
        let result = evaluate(tags: ["Forest Encounters", "Fantasy", "Forest"])

        #expect(result.tagRuleViolations.contains { $0.contains("repeats the title") })
    }

    @Test("Too few matching tag concepts fail")
    func tagConcepts() {
        let result = evaluate(tags: ["Roads", "Travel", "Weather"])

        #expect(result.conceptViolations.contains { $0.hasPrefix("tags: matched 0 of 2") })
        #expect(result.conceptScore < 1)
    }

    // MARK: - Banned words

    @Test("RPG, Setting, Mechanics and Use Case are banned in the description", arguments: [
        "A table of encounters for your RPG campaign in the forest.",
        "Random creatures that fit the setting of a dark forest.",
        "Encounter mechanics for travelling through the forest.",
        "Use case: random creatures the party meets in the forest.",
        "Zufällige Begegnungen im Wald, ein RPG-Werkzeug für Reisen.",
        "Die Mechanik für Begegnungen im Wald, einmal pro Wache."
    ])
    func bannedWordInDescription(description: String) {
        let result = evaluate(description: description)

        #expect(result.descriptionRuleViolations.contains { $0.contains("banned word") })
        #expect(!result.passed)
    }

    @Test("RPG, Setting, Mechanics and Use Case are banned in tags", arguments: [
        "RPG", "rpg", "Setting", "Mechanics", "Use Case", "use cases", "RPG Tools", "Dark Setting", "Mechanik", "RPG-Zufallstabelle"
    ])
    func bannedWordInTag(tag: String) {
        let result = evaluate(tags: ["Forest", "Encounter", tag])

        #expect(result.tagRuleViolations.contains { $0.contains("banned word") })
        #expect(!result.passed)
    }

    @Test("Banned words match whole words only")
    func bannedWordsAreWholeWords() {
        // "settings" in "Resettings" or "mechanical" must not count; "case" alone is fine.
        let result = evaluate(
            description: "Creatures and travelers in the forest, from a mechanical cart to a briefcase of coins.",
            tags: ["Forest", "Encounter", "Suitcase", "Cases"]
        )

        #expect(!result.descriptionRuleViolations.contains { $0.contains("banned word") })
        #expect(!result.tagRuleViolations.contains { $0.contains("banned word") })
    }

    // MARK: - Forbidden terms

    @Test("Forbidden terms are caught in title, description and tags")
    func forbiddenTerms() {
        let result = evaluate(
            title: "Wald Encounters",
            description: "Creatures in the Wald and what they do to the party.",
            tags: ["Encounter", "Wald", "Fantasy"]
        )

        #expect(result.titleRuleViolations.contains("contains forbidden term 'Wald'"))
        #expect(result.descriptionRuleViolations.contains("contains forbidden term 'Wald'"))
        #expect(result.tagRuleViolations.contains { $0.contains("forbidden term 'Wald'") })
    }

    @Test("Rule violations carry their field name")
    func violationPrefixes() {
        let result = evaluate(title: "", description: "", tags: ["Table"])

        #expect(result.ruleViolations.contains("title: is empty"))
        #expect(result.ruleViolations.contains("description: is empty"))
        #expect(result.ruleViolations.contains { $0.hasPrefix("tags: ") })
        #expect(!result.rulesPassed)
    }

    // MARK: - Fixtures

    @Test("Every fixture is a usable table", arguments: TableSummaryFixture.all)
    func fixtureIsUsable(fixture: TableSummaryFixture) {
        #expect(fixture.entries.count >= 6)
        #expect(fixture.entries.allSatisfy { !$0.name.isEmpty && !$0.content.isEmpty })
        #expect(!fixture.expectation.titleConcepts.isEmpty)
        #expect(!fixture.expectation.descriptionConcepts.isEmpty)
        #expect(fixture.expectation.tags.requiredGroupCount > 0)
        #expect(fixture.expectation.tags.forbiddenTerms.isEmpty, "forbidden terms belong to TableSummaryExpectation")
        // The analyzer cuts the text at 7,000 characters; the fixtures must fit so they are judged whole.
        #expect(fixture.entriesText.count < 7000)
    }

    @Test("A named fixture passes its name like the extraction screen")
    func entriesTextShape() {
        let text = TableSummaryFixture.docksideGossip.entriesText

        #expect(text.hasPrefix("Table: Dockside Gossip\n\n- 1: "))
        #expect(TableSummaryFixture.forestEncounters.entriesText.hasPrefix("- 1 Wolf pack: "))
    }

    @Test("Fixture names are unique")
    func uniqueNames() {
        let names = TableSummaryFixture.all.map(\.name)

        #expect(Set(names).count == names.count)
    }

    @Test("German output fixtures forbid English words, English output from German forbids German words")
    func languageFixturesForbidOtherLanguage() {
        for fixture in TableSummaryFixture.all where fixture.outputLanguage == "German" {
            #expect(!fixture.expectation.forbiddenTerms.isEmpty, "\(fixture.name)")
        }
        #expect(!TableSummaryFixture.mountainWeatherFromGerman.expectation.forbiddenTerms.isEmpty)
    }

    @Test("The sample dataset repeats every fixture once per run")
    func datasetSize() {
        #expect(TableSummarySample.dataset(runs: 3).count == TableSummaryFixture.all.count * 3)
    }
}

#endif
