// @copyright André Trettin

import Foundation
import FoundationModels

/// The sex as the model decides it. `unknown` comes first so it is the plain choice for a sheet
/// that shows nothing; the analyzer keeps `male` or `female` only with verified evidence.
/// Everything the model reads or streams says "gender", not "sex": with "sex" in the streamed
/// property names, the output guardrail stopped most analyses ("may contain sensitive content").
@Generable(description: "The character's gender: unknown unless a word on the sheet or in the portrait shows it")
enum CharacterGender: String, Codable, Sendable, CaseIterable {
    case unknown
    case male
    case female
}

/// What the model writes for a character sheet. Guided generation writes the properties in the
/// order they are declared, so the order is part of the prompt (measured on 2026-11-27):
/// - name and description first, as before: with race, occupation or gender streamed before
///   them, the output guardrail stopped up to half of the analyses ("may contain sensitive
///   content"), so the description cannot come after the race;
/// - the gender word before the gender, so the gender is quoted from the sheet. A gender chosen
///   to fit an invented name ("Tink" → female) quotes a word the sheet does not contain, and
///   `CharacterGender.verified` drops it;
/// - the traits last: generated before the description, they copied whole background sentences.
/// A regex guide on the traits (`.pattern`, also as `.element(.pattern(...))`) made every request
/// fail with `LanguageModelError -1` on the simulator, so trait length is left to the prompt and
/// `cleanedTrait`.
@Generable(description: "Extracted tag parts, name and description of a role-playing game character")
struct CharacterSummaryGeneration: Equatable, Sendable {

    @Guide(
        description: """
        The character's name, written as a name, never as a description. When the sheet starts \
        with a name, it is exactly that name. Otherwise an invented personal name that fits the \
        race and world. No label, no period.
        """
    )
    var name: String

    @Guide(
        description: """
        One or two sentences in the output language about who the character is: it names the race \
        by its name, not by a body type or size, and the class or occupation, and what makes them \
        special. Write about the \
        character, never about entries, values, a sheet or a table. Do not use the words \
        \(GeneratedTagRules.bannedWordsText).
        """
    )
    var description: String

    @Guide(
        description: """
        The character's race, species or people in 1 to 3 words. A name that only exists in the \
        game's own world stays unchanged, for example "Fjordzwerg" or "Kaiter"; a common race is \
        written in the output language. Human when the sheet names none.
        """
    )
    var race: String

    @Guide(
        description: """
        The character's class or occupation in 1 to 3 words, as the sheet names it, in the output \
        language. Only a monster without one gets its role in a fight.
        """
    )
    var occupation: String

    @Guide(
        description: """
        The exact word copied from the sheet or the portrait that shows the character's gender: a \
        pronoun, a gendered word for a person, or a clearly male or female first name. An empty \
        text when there is no such word, as for most monsters. Never a race, a class or a value.
        """
    )
    var genderWord: String

    @Guide(description: "male or female only when the gender word shows it, otherwise unknown. Never guess.")
    var gender: CharacterGender

    @Guide(
        description: """
        Exactly two short tags of 1 to 3 words, in the output language, for what is special about \
        this character, read from the sheet: values clearly higher than the others, the \
        background, the weapon or special abilities. A low or average value is no trait. Not the \
        race, occupation or gender again, no label, no sentence, and no generic word such as \
        Character, Stats or Attributes.
        """,
        .count(2)
    )
    var traits: [String]

}

extension CharacterSummaryGeneration {
    /// A trait without a short label and without trailing values: "Strength 17" becomes
    /// "Strength", "Weapon: Harpoon" becomes "Harpoon". A number inside ("60 ft cone") stays, and
    /// a label in front of a longer text stays, because the text after it is then a sentence.
    static func cleanedTrait(_ trait: String) -> String {
        var text = trait.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = text.firstIndex(of: ":") {
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let words = value.split(whereSeparator: \.isWhitespace)
            if !words.isEmpty, words.count <= GeneratedTagRules.maximumWordsPerTag {
                text = value
            }
        }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count > 1, let last = words.last, isNumber(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// "17", "+2", "70%", "3d10", "1W8": a value, not a word.
    private static func isNumber(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "+-%,.()"))
        guard let first = core.first, first.isNumber else { return false }
        return core.allSatisfy { $0.isNumber || "dDwW".contains($0) }
    }
}

/// Structured extraction result for a character sheet. The tags are separate parts, so each one
/// has its rule: race, class or occupation, sex (only when the sheet shows it) and two traits that
/// are special about this character. `summary` joins them into the title, description and tag
/// list the item stores.
public struct CharacterSummaryAnalysis: Equatable, Sendable, Codable {
    public var name: String
    public var description: String
    public var race: String
    public var occupation: String
    /// The sex as a word in the output language ("Female", "Weiblich"), empty when nothing shows it.
    public var sex: String
    public var traits: [String]

    public init(name: String, description: String, race: String, occupation: String, sex: String, traits: [String]) {
        self.name = name
        self.description = description
        self.race = race
        self.occupation = occupation
        self.sex = sex
        self.traits = traits
    }

    /// The result as the item stores it: the name as title, and the tags race, occupation, sex
    /// (left out when empty) and the two traits, cleaned like every generated tag list.
    public var summary: TableSummaryAnalysis {
        TableSummaryAnalysis(title: name, description: description, tags: Self.tags(race: race, occupation: occupation, sex: sex, traits: traits))
    }

    static func tags(race: String?, occupation: String?, sex: String?, traits: [String]?) -> [String] {
        let parts = [race, occupation, sex].compactMap { $0 } + (traits ?? [])
        return GeneratedTagRules.cleaned(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

// MARK: - Sex

extension CharacterGender {
    /// The sex the analysis keeps: `male` or `female` only when the evidence is a word that really
    /// is in the analyzed text (sheet, portrait, existing name). The model cannot be trusted to
    /// leave a monster's sex empty, but it cannot quote a word the sheet does not contain.
    static func verified(_ sex: CharacterGender?, evidence: String?, in sheetText: String) -> CharacterGender {
        guard let sex, sex != .unknown else { return .unknown }
        let quote = (evidence ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„«»‚‘’"))
        guard quote.count >= 2, quote.count <= 60, sheetText.localizedStandardContains(quote) else {
            return .unknown
        }
        return sex
    }

    /// The tag word for the sex in the output language (`OutputLanguage.englishName`), English
    /// for a language without its own words; empty for `unknown`. Fixed words instead of the
    /// model's, so the same sex is always the same tag.
    func word(in outputLanguage: String) -> String {
        let words: (male: String, female: String) = switch outputLanguage {
        case "German": ("Männlich", "Weiblich")
        case "French": ("Masculin", "Féminin")
        case "Spanish": ("Masculino", "Femenino")
        case "Italian": ("Maschile", "Femminile")
        case "Portuguese": ("Masculino", "Feminino")
        case "Dutch": ("Mannelijk", "Vrouwelijk")
        case "Polish": ("Mężczyzna", "Kobieta")
        case "Japanese": ("男性", "女性")
        default: ("Male", "Female")
        }
        return switch self {
        case .unknown: ""
        case .male: words.male
        case .female: words.female
        }
    }
}
