// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The character rules, how a result becomes the stored tags, the sheet text and the fixtures.
/// These need no Apple Intelligence and run in every test run, so a broken evaluation is found
/// before it judges the model.
@Suite("Character summary evaluator")
struct CharacterSummaryEvaluatorTests {
    private let evaluator = CharacterSummaryEvaluator()
    private let fixture = CharacterSummaryFixture.dwarfFighter

    private let good = CharacterSummaryAnalysis(
        name: "Brakka Ironvein",
        description: "A dwarf fighter and former mine guard who searches for the lost forge of her clan.",
        race: "Dwarf",
        occupation: "Fighter",
        sex: "Female",
        traits: ["Strong", "Hammer Expert"]
    )

    private func evaluate(
        _ change: (inout CharacterSummaryAnalysis) -> Void = { _ in },
        name existingName: String? = nil,
        expectation: CharacterSummaryExpectation? = nil
    ) -> CharacterSummaryVerdict {
        var analysis = good
        change(&analysis)
        return evaluator.evaluate(
            analysis,
            existingName: existingName ?? fixture.characterName,
            expectation: expectation ?? fixture.expectation
        )
    }

    @Test("A good character summary passes")
    func goodSummary() {
        let result = evaluate()

        #expect(result.passed, "\(result.violations)")
        #expect(result.conceptScore == 1)
        #expect(result.tags == ["Dwarf", "Fighter", "Female", "Strong", "Hammer Expert"])
    }

    // MARK: - Stored tags

    @Test("The stored tags are race, occupation, sex and the traits; no sex leaves four")
    func summaryTags() {
        var analysis = good
        analysis.sex = "  "

        #expect(good.summary.tags == ["Dwarf", "Fighter", "Female", "Strong", "Hammer Expert"])
        #expect(analysis.summary.tags == ["Dwarf", "Fighter", "Strong", "Hammer Expert"])
        #expect(good.summary.title == "Brakka Ironvein")
        #expect(good.summary.description == good.description)
    }

    @Test("A trait that repeats the race is dropped from the stored tags and fails")
    func repeatedTrait() {
        let result = evaluate { $0.traits = ["Dwarf", "Strong"] }

        #expect(result.tags == ["Dwarf", "Fighter", "Female", "Strong"])
        #expect(result.tagRuleViolations.contains { $0.contains("repeats the race") })
    }

    // MARK: - Name

    @Test("A named character must keep its name")
    func keepsName() {
        let result = evaluate { $0.name = "Dwarven Mine Guard" }

        #expect(result.nameRuleViolations == ["'Dwarven Mine Guard' does not keep the name 'Brakka Ironvein'"])
    }

    @Test("An unnamed character gets a name, not a description", arguments: [
        "Goblin Skirmisher", "Skirmisher", "Character", "Name: Snik", "Snik the very quick little goblin"
    ])
    func inventedNameMustBeAName(name: String) {
        let goblin = CharacterSummaryFixture.goblinSkirmisher
        let result = evaluate({ $0.name = name }, name: "", expectation: goblin.expectation)

        #expect(!result.nameRuleViolations.isEmpty)
    }

    @Test("An invented personal name passes", arguments: ["Snik", "Hilde Steinfaust", "Grukk Ashtooth"])
    func inventedName(name: String) {
        let goblin = CharacterSummaryFixture.goblinSkirmisher
        let result = evaluate({ $0.name = name }, name: "", expectation: goblin.expectation)

        #expect(result.nameRuleViolations.isEmpty, "\(result.nameRuleViolations)")
    }

    // MARK: - Description

    @Test("A description about entries or a table fails", arguments: [
        "These entries detail the attributes and background of a dwarf fighter.",
        "A dwarf fighter. This table captures her clan and forge.",
        "Die Einträge beschreiben eine Ärztin aus Berlin."
    ])
    func formDescription(description: String) {
        let result = evaluate { $0.description = description }

        #expect(result.descriptionRuleViolations.contains { $0.contains("banned word") })
    }

    @Test("A description of three sentences fails")
    func longDescription() {
        let result = evaluate { $0.description = "A dwarf. A fighter. She seeks the forge of her clan." }

        #expect(result.descriptionRuleViolations.contains { $0.contains("3 sentences") })
    }

    // MARK: - Race and occupation

    @Test("A race of the game's own world is expected as written")
    func ownWorldRace() {
        let fjordzwerg = CharacterSummaryFixture.fjordzwergWalfaenger.expectation
        let kept = evaluate({ $0.race = "Fjordzwerg" }, expectation: fjordzwerg)
        let generalized = evaluate({ $0.race = "Zwerg" }, expectation: fjordzwerg)

        #expect(!kept.conceptViolations.contains { $0.hasPrefix("race") })
        #expect(generalized.conceptViolations.contains { $0.hasPrefix("race") })
    }

    @Test("Race and occupation must be short and without a label")
    func partFormat() {
        let result = evaluate {
            $0.race = "Race: Dwarf"
            $0.occupation = "Former mine guard of the clan"
        }

        #expect(result.tagRuleViolations.contains("race 'Race: Dwarf' uses a 'label: value' form"))
        #expect(result.tagRuleViolations.contains { $0.contains("occupation 'Former mine guard of the clan' has more than 3 words") })
    }

    @Test("A monster passes with any occupation")
    func monsterOccupation() {
        let wyrm = CharacterSummaryFixture.ashWyrm.expectation
        let result = evaluate({
            $0.race = "Dragon"
            $0.occupation = "Lair Tyrant"
            $0.traits = ["Fire Breath", "Armored"]
            $0.description = "An ancient dragon that breathes burning ash from its volcano lair."
        }, name: "Brakka Ironvein", expectation: wyrm)

        #expect(!result.conceptViolations.contains { $0.hasPrefix("occupation") })
    }

    // MARK: - Sex

    @Test("Sex: shown and right passes, missing, wrong or guessed fails")
    func sex() {
        let goblin = CharacterSummaryFixture.goblinSkirmisher.expectation
        let german = CharacterSummaryFixture.aerztinBerlin.expectation

        #expect(evaluate().sexViolations.isEmpty)
        #expect(evaluate({ $0.sex = "Weiblich" }, expectation: german).sexViolations.isEmpty)
        #expect(evaluate { $0.sex = "" }.sexViolations == ["sex is missing although the sheet or portrait shows it"])
        #expect(evaluate { $0.sex = "Male" }.sexViolations == ["sex 'Male' is wrong, expected female"])
        #expect(evaluate({ $0.sex = "Male" }, expectation: goblin).sexViolations == ["sex 'Male' is guessed, nothing shows it"])
        #expect(evaluate({ $0.sex = "" }, expectation: goblin).sexViolations.isEmpty)
    }

    @Test("A wrong sex is a tag rule violation too")
    func sexIsTagRule() {
        #expect(evaluate { $0.sex = "Male" }.tagRuleViolations.contains("sex 'Male' is wrong, expected female"))
    }

    // MARK: - Traits

    @Test("Exactly two traits")
    func traitCount() {
        #expect(evaluate { $0.traits = ["Strong"] }.tagRuleViolations.contains("1 traits, expected 2"))
        #expect(evaluate { $0.traits = ["Strong", "Loyal", "Stubborn"] }.tagRuleViolations.contains("3 traits, expected 2"))
    }

    @Test("Generic traits fail", arguments: ["Character", "Stats", "Attributes", "Background", "NPC", "Werte"])
    func genericTrait(trait: String) {
        let result = evaluate { $0.traits = [trait, "Strong"] }

        #expect(result.tagRuleViolations.contains { $0.contains("is generic") })
    }

    @Test("A trait must show what the values and background support")
    func traitConcept() {
        let result = evaluate { $0.traits = ["Cheerful", "Musical"] }

        #expect(result.conceptViolations.contains { $0.hasPrefix("traits") })
    }

    // MARK: - Sheet text

    @Test("Links in the values reach the model as their labels")
    func linksAreStripped() {
        #expect(fixture.entries.contains { $0.value.contains("](") }, "the fixture should hold real links")
        #expect(!fixture.entriesText.contains("]("))
        #expect(!fixture.entriesText.contains("://"))
        #expect(fixture.entriesText.contains("- Hit Points: Constitution+Level*10"))
    }

    @Test("The portrait's description and tags follow the values")
    func portraitText() {
        let text = CharacterSummaryFixture.freighterPilot.entriesText

        #expect(text.hasPrefix("Character: Rook Vashti\n\n- Role: "))
        #expect(text.contains("- Blaster: 2d6\n\nPortrait: A woman in her thirties"))
        #expect(text.hasSuffix("\nPortrait tags: Pilot, Spaceport, Cyberpunk"))
        #expect(!fixture.entriesText.contains("Portrait"))
    }

    @Test("A long portrait description is cut, empty portrait tags are left out")
    func portraitBounds() {
        let text = TextSummaryExtractionFormatter.formatCharacter(
            title: "Character",
            name: "",
            entries: [("Class", "Bard")],
            portraitDescription: String(repeating: "a", count: 2000),
            portraitTags: [" ", ""]
        )

        #expect(text == "- Class: Bard\n\nPortrait: " + String(repeating: "a", count: TextSummaryExtractionFormatter.maximumPortraitDescriptionLength))
    }

    // MARK: - Fixtures

    @Test("Every fixture is a usable character", arguments: CharacterSummaryFixture.all)
    func fixtureIsUsable(fixture: CharacterSummaryFixture) {
        #expect(fixture.entries.count >= 6)
        #expect(fixture.entries.allSatisfy { !$0.name.isEmpty && !$0.value.isEmpty })
        #expect(!fixture.expectation.race.isEmpty)
        #expect(!fixture.expectation.traitConcepts.isEmpty)
        #expect(!fixture.expectation.descriptionConcepts.isEmpty)
        // An invented name is checked against descriptive words, a given name is kept.
        #expect(fixture.characterName.isEmpty == !fixture.expectation.descriptiveNameTerms.isEmpty)
        // The analyzer cuts the text at 7,000 characters; the fixtures must fit so they are judged whole.
        #expect(fixture.entriesText.count < 7000)
    }

    @Test("Fixture names are unique")
    func uniqueNames() {
        let names = CharacterSummaryFixture.all.map(\.name)

        #expect(Set(names).count == names.count)
    }

    @Test("Fixtures cover named, unnamed, no sex, portrait-only sex and a race of the game's world")
    func coverage() {
        let all = CharacterSummaryFixture.all

        #expect(all.contains { $0.characterName.isEmpty })
        #expect(all.contains { !$0.characterName.isEmpty })
        #expect(all.contains { $0.expectation.sex == nil })
        #expect(all.contains { $0.expectation.sex == .male })
        #expect(all.contains { !$0.portraitDescription.isEmpty })
        #expect(CharacterSummaryFixture.fjordzwergWalfaenger.expectation.race == ["fjordzwerg"])
    }

    @Test("German output fixtures forbid English words, English output from German forbids German words")
    func languageFixturesForbidOtherLanguage() {
        for fixture in CharacterSummaryFixture.all where fixture.outputLanguage == "German" {
            #expect(!fixture.expectation.forbiddenTerms.isEmpty, "\(fixture.name)")
        }
        #expect(!CharacterSummaryFixture.elvenRangerFromGerman.expectation.forbiddenTerms.isEmpty)
    }

    @Test("The sample dataset repeats every fixture once per run")
    func datasetSize() {
        #expect(CharacterSummarySample.dataset(runs: 3).count == CharacterSummaryFixture.all.count * 3)
    }
}

#endif
