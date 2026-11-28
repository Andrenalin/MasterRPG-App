// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The tag rules are shared by the PDF, photo and table analysis and by the evaluation that judges
/// them, so a change in one place has to show in all of them.
@Suite("Generated tag rules")
struct GeneratedTagRulesTests {
    @Test("Three to five tags")
    func count() {
        #expect(GeneratedTagRules.countRange == 3...5)
        #expect(GeneratedTagRules.countText == "3 to 5")
    }

    @Test("The banned words are RPG, Setting, Mechanics and Use Case")
    func bannedWords() {
        #expect(GeneratedTagRules.bannedWords == ["RPG", "Setting", "Mechanics", "Use Case"])
        #expect(GeneratedTagRules.bannedWordsText == "\"RPG\", \"Setting\", \"Mechanics\" or \"Use Case\"")
    }

    @Test("The rules name every banned and generic word, plus the extras of a kind")
    func rulesText() {
        let rules = GeneratedTagRules.rules(extraGenericTags: ["Image"])

        for word in GeneratedTagRules.bannedWords + GeneratedTagRules.genericTags + ["Image"] {
            #expect(rules.contains("\"\(word)\""), "\(word)")
        }
        #expect(rules.contains("1 to 3 words"))
    }

    @Test("The guide text carries the count and the rules")
    func guideText() {
        let text = GeneratedTagRules.guideDescription(contents: "One tag says the kind.")

        #expect(text.hasPrefix("3 to 5 short tags. One tag says the kind."))
        #expect(text.contains(GeneratedTagRules.rules()))
    }

    @Test("A label before a value is cut to the value", arguments: [
        ("Ausruestung: Trading", "Trading"),
        ("Gueter: Lebensmittel", "Lebensmittel"),
        ("Genre: Fantasy", "Fantasy"),
        ("Setting : Dark Fen ", "Dark Fen"),
        ("Gear: Weapons: Swords", "Swords"),
        ("Loot:", "Loot"),
        ("Dungeon", "Dungeon")
    ])
    func labelIsCut(tag: String, value: String) {
        #expect(GeneratedTagRules.withoutLabel(tag) == value)
    }

    @Test("Cleaned tags have no labels, no repeats and at most five entries")
    func cleaned() {
        let tags = GeneratedTagRules.cleaned([
            "Ausruestung: Trading", "Gueter: Lebensmittel", "trading", " ", "Handel", "Karawane", "Wüste", "Oase"
        ])

        #expect(tags == ["Trading", "Lebensmittel", "Handel", "Karawane", "Wüste"])
        #expect(!tags.contains { $0.contains(":") })
    }

    @Test("A tag that repeats the title is dropped", arguments: [
        ("Wurzelnest", "Wurzelnest"),
        ("wurzelnest ", "Wurzelnest"),
        ("Feinschmecker", "feinschmecker"),
        ("Räuber", "Rauber"),
        ("Titel: Wurzelnest", "Wurzelnest")
    ])
    func titleIsDropped(tag: String, title: String) {
        let tags = GeneratedTagRules.cleaned(["Abenteuer", tag, "Kobolde", "Kult"], title: title)

        #expect(tags == ["Abenteuer", "Kobolde", "Kult"])
    }

    @Test("A tag that only contains the title is kept")
    func partOfTitleIsKept() {
        let tags = GeneratedTagRules.cleaned(["Abenteuer", "Wurzelnest", "Kobolde"], title: "Angriff auf das Wurzelnest")

        #expect(tags == ["Abenteuer", "Wurzelnest", "Kobolde"])
    }

    @Test("A generic tag that fits every RPG document is dropped", arguments: [
        "Game", "Spiel", "Rollenspiel", "Role-playing game", "Roleplaying game", "role playing Game",
        "Pen & Paper", "Pen-and-Paper", "Tabletop", "TTRPG", "RPG", "Genre", "System", "Setting", "Genre: System"
    ])
    func genericIsDropped(tag: String) {
        let tags = GeneratedTagRules.cleaned([tag, "Smugglers", "Outer Colonies", "Cyberware"], title: "Starlane Protocol")

        #expect(tags == ["Smugglers", "Outer Colonies", "Cyberware"])
    }

    @Test("A tag with a banned word as a whole word is dropped", arguments: [
        "RPG-Zufallstabelle", "Dark Setting", "Combat Mechanics", "Use Case Loot", "Kampf Mechanik", "Settings"
    ])
    func bannedWordIsDropped(tag: String) {
        let tags = GeneratedTagRules.cleaned(["Dungeon", tag, "Undead", "Crypt"], title: "The Crypt of Ash")

        #expect(tags == ["Dungeon", "Undead", "Crypt"])
    }

    @Test("Words that only contain a banned or generic word are kept")
    func specificTagsAreKept() {
        let tags = GeneratedTagRules.cleaned(
            ["Mechanical Cart", "Briefcase", "Game system", "Spielwelt", "Regelwerk"], title: "Core Rules"
        )

        #expect(tags == ["Mechanical Cart", "Briefcase", "Game system", "Spielwelt", "Regelwerk"])
    }

    @Test("The spare candidates fill the dropped slots, no more than five remain")
    func sparesFillUp() {
        let tags = GeneratedTagRules.cleaned(
            ["Fantasy", "Wurzelnest", "Kobolde", "Rollenspiel", "Höhle", "Kult", "Abenteuer"], title: "Wurzelnest"
        )

        #expect(tags == ["Fantasy", "Kobolde", "Höhle", "Kult", "Abenteuer"])
    }

    @Test("Seven valid candidates are cut to five")
    func candidatesAreCut() {
        let tags = GeneratedTagRules.cleaned(["A1", "B2", "C3", "D4", "E5", "F6", "G7"], title: "Title")

        #expect(tags.count == GeneratedTagRules.countRange.upperBound)
    }

    @Test("Without a title the photo and table rules keep generic tags")
    func cleanedWithoutTitleIsUnchanged() {
        #expect(GeneratedTagRules.cleaned(["Setting", "Game", "Forest"]) == ["Setting", "Game", "Forest"])
    }

    @Test("The rules forbid colons and give a German label example")
    func rulesMentionLabels() {
        let rules = GeneratedTagRules.rules()

        #expect(rules.contains("Never use a colon"))
        #expect(rules.contains("Ausrüstung: Handel"))
    }

    @Test("The photo prompt instructions use the shared rules")
    func photoPrompt() {
        #expect(PhotoSummaryAnalyzer.prompt(outputLanguage: "German").contains("3 to 5 specific tags"))
    }

    @Test("The evaluation judges with the same count and words")
    func evaluatorReadsTheRules() {
        let evaluator = PdfTagEvaluator()

        #expect(evaluator.allowedCount == GeneratedTagRules.countRange)
        for word in GeneratedTagRules.bannedWords {
            #expect(evaluator.bannedWords.contains(word))
        }
    }

    @Test("A banned word in any tag fails every kind of evaluation", arguments: [
        "RPG", "Setting", "Mechanics", "Use Case", "RPG Tools", "Dark Setting", "Mechanik", "RPG-Zufallstabelle"
    ])
    func bannedTag(tag: String) {
        let result = PdfTagEvaluator().evaluate(
            tags: ["Dungeon", "Undead", tag],
            title: "The Crypt",
            expectation: PdfTagExpectation(conceptGroups: [["dungeon"]])
        )

        #expect(result.violations.contains { $0.contains("banned word") })
    }

    @Test("Banned words are whole words")
    func wholeWords() {
        let evaluator = PdfTagEvaluator()

        #expect(evaluator.bannedWordViolations(in: "Mechanical Cart").isEmpty)
        #expect(evaluator.bannedWordViolations(in: "Briefcase").isEmpty)
        #expect(evaluator.bannedWordViolations(in: "Use Case: loot").count == 1)
    }
}

#endif
