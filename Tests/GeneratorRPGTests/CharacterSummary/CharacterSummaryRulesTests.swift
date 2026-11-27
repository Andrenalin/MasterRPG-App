// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The parts of the Character analysis that are code, not prompt: the player's name check, the
/// trait cleanup and the German class and race glossary. No Apple Intelligence needed.
@Suite("Character summary rules")
struct CharacterSummaryRulesTests {
    private let sheet = """
    Charakter: Helene Barth

    - Klasse: Waldläuferin
    - Volk: Elfe
    - Hintergrund: Sie bewacht die Grenze.
    """

    // MARK: - Player name

    @Test("A player's name is kept when it is on the sheet and not the character's name", arguments: ["Jonas Reuter", "\"Jonas Reuter\"", " jonas reuter "])
    func playerOnSheet(player: String) {
        let sheet = sheet + "\n- Spieler: Jonas Reuter"

        #expect(CharacterSummaryGeneration.verifiedPlayerName(player, in: sheet, characterName: "Helene Barth").localizedStandardContains("Jonas Reuter"))
    }

    @Test("An invented player or the character's own name is dropped", arguments: ["", " ", "x", "Sam Miller", "Helene Barth", "Helene", String(repeating: "a", count: 61)])
    func playerDropped(player: String) {
        #expect(CharacterSummaryGeneration.verifiedPlayerName(player, in: sheet, characterName: "Helene Barth").isEmpty)
    }

    @Test("A missing player stays empty")
    func playerMissing() {
        #expect(CharacterSummaryGeneration.verifiedPlayerName(nil, in: sheet, characterName: "").isEmpty)
    }

    // MARK: - Occupation

    @Test("An empty occupation is taken from a class word in the character's name", arguments: [
        ("Aquater Kämpfer", "German", "Kämpfer"), ("Aquater Kämpfer", "English", "Fighter"),
        ("Grimbart der Schmied", "German", "Schmied"), ("Brakka Ironvein", "German", ""), ("", "German", "")
    ])
    func occupationFromName(name: String, language: String, occupation: String) {
        #expect(CharacterSummaryGeneration.occupation(nil, characterName: name, outputLanguage: language) == occupation)
        #expect(CharacterSummaryGeneration.occupation("  ", characterName: name, outputLanguage: language) == occupation)
    }

    @Test("The model's occupation wins over the name")
    func occupationFromModel() {
        #expect(CharacterSummaryGeneration.occupation(" Söldner ", characterName: "Aquater Kämpfer", outputLanguage: "German") == "Söldner")
    }

    // MARK: - Traits

    @Test("Trailing values and short labels leave a trait", arguments: [
        ("Strength 17", "Strength"), ("Medizin 70", "Medizin"), ("Weapon: Harpoon", "Harpoon"),
        ("60 ft cone", "60 ft cone"), ("Initiative +2", "Initiative"), ("Bite 2d10", "Bite"), ("Nimble Escape", "Nimble Escape"),
        ("Hochseefahrt", "Hochseefahrt"), ("17", "17")
    ])
    func cleanedTrait(trait: String, cleaned: String) {
        #expect(CharacterSummaryGeneration.cleanedTrait(trait) == cleaned)
    }

    @Test("A label in front of a sentence stays, so the sentence is not passed off as a trait")
    func labelBeforeSentence() {
        let trait = "Background: A former mine guard who searches for the forge"

        #expect(CharacterSummaryGeneration.cleanedTrait(trait) == trait)
    }

    // MARK: - Glossary

    @Test("German class and race words on the sheet get their game term")
    func glossaryHints() {
        let hints = CharacterTermGlossary.hints(in: sheet, outputLanguage: "English")

        #expect(hints == [
            "\"Waldläuferin\" is the class Ranger.",
            "\"Elfe\" is the race Elf."
        ])
    }

    @Test("German output needs no glossary")
    func glossaryGermanOutput() {
        #expect(CharacterTermGlossary.hints(in: sheet, outputLanguage: "German").isEmpty)
    }

    @Test("Only whole words match: world-specific races and longer words stay untouched", arguments: [
        "Volk: Fjordzwerg", "Beruf: Wirtschafter", "Stufe: elf", "Waffe: Zwergenaxt", "Klasse: Ranger"
    ])
    func glossaryWholeWords(text: String) {
        #expect(CharacterTermGlossary.matches(in: text).isEmpty)
    }

    @Test("Male forms and races match case insensitively")
    func glossaryMaleForms() {
        let matches = CharacterTermGlossary.matches(in: "- Klasse: krieger\n- Volk: ZWERG")

        #expect(matches.map(\.english) == ["Fighter", "Dwarf"])
    }

    @Test("The prompt block lists the hints only when there are some")
    func glossaryPromptBlock() {
        let text = CharacterSummaryAnalyzer.glossaryText(for: sheet, outputLanguage: "English")

        #expect(text.hasPrefix("\nWords on this sheet and their game terms, to write in English:\n- \"Waldläuferin\""))
        #expect(CharacterSummaryAnalyzer.glossaryText(for: "- Class: Bard", outputLanguage: "English").isEmpty)
    }

    @Test("Every glossary word is unique, so a sheet word maps to one term")
    func glossaryUniqueWords() {
        let words = CharacterTermGlossary.terms.map { $0.german.lowercased() }

        #expect(Set(words).count == words.count)
    }
}

#endif
