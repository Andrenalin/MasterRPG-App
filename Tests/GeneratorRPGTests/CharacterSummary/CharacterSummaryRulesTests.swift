// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The parts of the Character analysis that are code, not prompt: the sex evidence check, the
/// fixed sex words and the German class and race glossary. No Apple Intelligence needed.
@Suite("Character summary rules")
struct CharacterSummaryRulesTests {
    private let sheet = """
    Charakter: Helene Barth

    - Klasse: Waldläuferin
    - Volk: Elfe
    - Hintergrund: Sie bewacht die Grenze.
    """

    // MARK: - Sex evidence

    @Test("A sex is kept when its evidence is a word of the sheet", arguments: ["Sie", "Waldläuferin", "Helene", "\"sie\"", " waldlauferin "])
    func evidenceOnSheet(evidence: String) {
        #expect(CharacterGender.verified(.female, evidence: evidence, in: sheet) == .female)
    }

    @Test("A sex without evidence from the sheet is dropped", arguments: ["", " ", "she", "Tink", "x", String(repeating: "a", count: 61)])
    func evidenceMissing(evidence: String) {
        #expect(CharacterGender.verified(.female, evidence: evidence, in: sheet) == .unknown)
    }

    @Test("Unknown and a missing sex stay unknown")
    func unknownStaysUnknown() {
        #expect(CharacterGender.verified(.unknown, evidence: "Sie", in: sheet) == .unknown)
        #expect(CharacterGender.verified(nil, evidence: "Sie", in: sheet) == .unknown)
        #expect(CharacterGender.verified(.male, evidence: nil, in: sheet) == .unknown)
    }

    @Test("The sex word follows the output language, English for others", arguments: [
        ("English", CharacterGender.female, "Female"), ("German", .male, "Männlich"), ("German", .female, "Weiblich"),
        ("Japanese", .female, "女性"), ("Klingon", .male, "Male"), ("German", .unknown, "")
    ])
    func sexWord(language: String, sex: CharacterGender, word: String) {
        #expect(sex.word(in: language) == word)
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
            "\"Waldläuferin\" is the female form of the class Ranger.",
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
        #expect(matches.allSatisfy { !$0.isFemaleForm })
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
