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
        traits: ["Strong", "Hammer Expert"],
        playerName: "Mara Lindqvist"
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
        #expect(result.tags == ["Dwarf", "Fighter", "Strong", "Hammer Expert", "Mara Lindqvist"])
    }

    // MARK: - Stored tags

    @Test("The stored tags are race, occupation, traits and player; empty parts are left out")
    func summaryTags() {
        var animal = good
        animal.race = "Brown bear"
        animal.occupation = " "
        animal.traits = []
        animal.playerName = ""

        #expect(good.summary.tags == ["Dwarf", "Fighter", "Strong", "Hammer Expert", "Mara Lindqvist"])
        #expect(animal.summary.tags == ["Brown bear"])
        #expect(good.summary.title == "Brakka Ironvein")
        #expect(good.summary.description == good.description)
    }

    @Test("No more than two traits are stored")
    func storedTraitLimit() {
        var analysis = good
        analysis.traits = ["Strong", "Loyal", "Stubborn"]

        #expect(analysis.summary.tags == ["Dwarf", "Fighter", "Strong", "Loyal", "Mara Lindqvist"])
    }

    @Test("A trait that repeats the race is dropped from the stored tags and fails")
    func repeatedTrait() {
        let result = evaluate { $0.traits = ["Dwarf", "Strong"] }

        #expect(result.tags == ["Dwarf", "Fighter", "Strong", "Mara Lindqvist"])
        #expect(result.tagRuleViolations.contains { $0.contains("repeats the race") })
    }

    @Test("Two to five tags: the race alone is too few")
    func tagCount() {
        let result = evaluate {
            $0.occupation = ""
            $0.traits = []
            $0.playerName = ""
        }

        #expect(result.tagRuleViolations.contains { $0.contains("1 stored tags") })
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

    @Test("A monster without a class keeps the occupation empty; a guessed one fails")
    func monsterOccupation() {
        let wyrm = CharacterSummaryFixture.ashWyrm.expectation
        let dragon: (inout CharacterSummaryAnalysis) -> Void = {
            $0.race = "Dragon"
            $0.occupation = ""
            $0.traits = ["Fire Breath", "Armored"]
            $0.playerName = ""
            $0.description = "An ancient dragon that breathes burning ash from its volcano lair."
        }
        let empty = evaluate(dragon, expectation: wyrm)
        let guessed = evaluate({ dragon(&$0); $0.occupation = "Lair Tyrant" }, expectation: wyrm)

        #expect(empty.tagRuleViolations.isEmpty, "\(empty.tagRuleViolations)")
        #expect(guessed.tagRuleViolations.contains("occupation 'Lair Tyrant' is guessed, the sheet names none"))
    }

    @Test("A character with a class must name it")
    func missingOccupation() {
        #expect(evaluate { $0.occupation = "" }.tagRuleViolations.contains("occupation is empty"))
    }

    // MARK: - Player

    @Test("Player: named and right passes, missing, wrong or invented fails")
    func player() {
        let goblin = CharacterSummaryFixture.goblinSkirmisher.expectation

        #expect(evaluate().playerViolations.isEmpty)
        #expect(evaluate { $0.playerName = "mara lindqvist" }.playerViolations.isEmpty)
        #expect(evaluate { $0.playerName = "" }.playerViolations == ["player's name is missing although the sheet names it"])
        #expect(evaluate { $0.playerName = "Jonas" }.playerViolations == ["player 'Jonas' is wrong, expected 'Mara Lindqvist'"])
        #expect(evaluate({ $0.playerName = "Sam" }, expectation: goblin).playerViolations == ["player 'Sam' is invented, the sheet names none"])
        #expect(evaluate({ $0.playerName = "" }, expectation: goblin).playerViolations.isEmpty)
    }

    @Test("A wrong player is a tag rule violation too")
    func playerIsTagRule() {
        #expect(evaluate { $0.playerName = "Jonas" }.tagRuleViolations.contains("player 'Jonas' is wrong, expected 'Mara Lindqvist'"))
    }

    // MARK: - Traits

    @Test("Zero to two traits")
    func traitCount() {
        #expect(!evaluate { $0.traits = [] }.tagRuleViolations.contains { $0.contains("traits, allowed") })
        #expect(!evaluate { $0.traits = ["Strong"] }.tagRuleViolations.contains { $0.contains("traits, allowed") })
        #expect(evaluate { $0.traits = ["Strong", "Loyal", "Stubborn"] }.tagRuleViolations.contains("3 traits, allowed are 0...2"))
    }

    @Test("No traits is no concept miss")
    func noTraitsNoConceptMiss() {
        let result = evaluate { $0.traits = [] }

        #expect(!result.conceptViolations.contains { $0.hasPrefix("traits") })
        #expect(result.conceptScore == 1)
    }

    @Test("A trait that repeats the occupation fails")
    func traitRepeatsOccupation() {
        #expect(evaluate { $0.traits = ["Fighter", "Strong"] }.tagRuleViolations.contains("trait 'Fighter' repeats the race or occupation"))
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

        #expect(text == "- Class: Bard\n\nPortrait: " + String(repeating: "a", count: TextSummaryExtractionFormatter.maximumPhotoDescriptionLength))
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

    @Test("An expected player's name is a value of the sheet", arguments: CharacterSummaryFixture.all.filter { $0.expectation.playerName != nil })
    func playerOnSheet(fixture: CharacterSummaryFixture) {
        #expect(fixture.entriesText.contains(fixture.expectation.playerName ?? "-"))
    }

    @Test("Fixture names are unique")
    func uniqueNames() {
        let names = CharacterSummaryFixture.all.map(\.name)

        #expect(Set(names).count == names.count)
    }

    @Test("Fixtures cover named, unnamed, players, no occupation, an animal, portraits and a race of the game's world")
    func coverage() {
        let all = CharacterSummaryFixture.all

        #expect(all.contains { $0.characterName.isEmpty })
        #expect(all.contains { !$0.characterName.isEmpty })
        #expect(all.contains { $0.expectation.playerName != nil })
        #expect(all.contains { $0.expectation.playerName == nil })
        #expect(all.contains { $0.expectation.occupation.isEmpty })
        #expect(CharacterSummaryFixture.caveBear.expectation.race == ["bear"])
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
