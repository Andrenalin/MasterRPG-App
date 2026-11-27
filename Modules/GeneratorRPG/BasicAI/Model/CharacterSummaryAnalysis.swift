// @copyright André Trettin

import Foundation
import FoundationModels

/// What the model writes for a character sheet. Guided generation writes the properties in the
/// order they are declared, so the order is part of the prompt (measured on 2026-11-27):
/// - name and description first: with tag parts streamed before them, the output guardrail
///   stopped up to half of the analyses ("may contain sensitive content");
/// - the traits last: generated before the description, they copied whole background sentences.
/// The tags are race, class or occupation (only when the sheet names one), up to two traits and
/// the player's name (only when the sheet names a player, checked in code with
/// `verifiedPlayerName`). There is no sex tag.
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
        The character's race, species or people in 1 to 3 words, always given: a people such as \
        human, dwarf, elf or gnome; the animal's name for an animal; the monster's own name for a \
        monster. A \
        name that only exists in the game's own world stays unchanged, for example "Fjordzwerg" \
        or "Kaiter"; a common race is written in the output language. Human for a person when the \
        sheet names no race.
        """
    )
    var race: String

    @Guide(
        description: """
        The character's class, occupation or role in 1 to 3 words, in the output language, only \
        when the sheet or the portrait names one. An empty text when nothing names one, as for \
        most animals and monsters. Never guess.
        """
    )
    var occupation: String

    @Guide(
        description: """
        The name of the player, the real person who plays this character, copied exactly from \
        the sheet when a value names the player. An empty text when the sheet names no player. \
        Never the character's own name.
        """
    )
    var playerName: String

    @Guide(
        description: """
        Up to two short tags of 1 to 3 words, in the output language, for what is special about \
        this character, only what the sheet or portrait says, never what you know about the race: \
        the value clearly higher than the others, or a special feature such as armor, a natural \
        ability, a talent or the background; an ordinary weapon only when nothing else stands out. \
        As close to the sheet's word as the output language allows, not a new word; for a text \
        value, what it says, never its label. None when nothing stands out. A low or average value is no trait. Not the race or the class or occupation again, no \
        label, no sentence, and no generic word such as Character, Stats or Attributes.
        """,
        .maximumCount(2)
    )
    var traits: [String]

}

extension CharacterSummaryGeneration {
    /// A trait without a short label and without trailing values: "Strength 17" becomes
    /// "Strength", "Weapon: Harpoon" becomes "Harpoon". A number inside ("60 ft cone") stays, and
    /// a label in front of a longer text stays, because the text after it is then a sentence.
    static func cleanedTrait(_ trait: String) -> String {
        var text = trait.trimmingCharacters(in: .whitespacesAndNewlines)
        // A formula copied from a value: "Schlag+WB+mag" → "Schlag", "Geschicklichkeit+2" → "Geschicklichkeit".
        if let plus = text.firstIndex(of: "+"), plus != text.startIndex {
            text = text[..<plus].trimmingCharacters(in: .whitespaces)
        }
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

    /// Whether a cleaned trait is worth a tag: not empty, not only a value ("3") and not a label or
    /// generic word ("Background", "Hintergrund"), which the model copies from the sheet.
    static func isUsefulTrait(_ trait: String) -> Bool {
        let key = trait.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.contains(where: \.isLetter) && !isNumber(key) && !genericTraitWords.contains(key)
    }

    /// Words that say nothing about a character, English and German.
    static let genericTraitWords: Set<String> = [
        "character", "characters", "stats", "statistics", "attributes", "values", "profile",
        "background", "personal", "individual", "npc", "player character", "monster", "creature",
        "charakter", "werte", "attribute", "profil", "hintergrund", "person", "figur", "nsc",
        "spielercharakter", "kreatur"
    ]

    /// "17", "+2", "70%", "3d10", "1W8": a value, not a word.
    private static func isNumber(_ word: String) -> Bool {
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "+-%,.()"))
        guard let first = core.first, first.isNumber else { return false }
        return core.allSatisfy { $0.isNumber || "dDwW".contains($0) }
    }
}

/// Structured extraction result for a character sheet. The tags are separate parts, so each one
/// has its rule: the race, the class or occupation (only when the sheet names one), up to two
/// traits that are special about this character and the player's name (only when the sheet names
/// one). `summary` joins them into the title, description and the 2 to 5 tags the item stores.
public struct CharacterSummaryAnalysis: Equatable, Sendable, Codable {
    public var name: String
    public var description: String
    public var race: String
    /// Empty when the sheet names no class or occupation.
    public var occupation: String
    /// Up to two.
    public var traits: [String]
    /// The player who plays the character, empty when the sheet names none.
    public var playerName: String

    public init(name: String, description: String, race: String, occupation: String, traits: [String], playerName: String = "") {
        self.name = name
        self.description = description
        self.race = race
        self.occupation = occupation
        self.traits = traits
        self.playerName = playerName
    }

    /// The result as the item stores it: the name as title, and the tags race, occupation, the
    /// traits and the player's name, empty parts left out, cleaned like every generated tag list.
    public var summary: TableSummaryAnalysis {
        TableSummaryAnalysis(title: name, description: description, tags: Self.tags(race: race, occupation: occupation, traits: traits, playerName: playerName))
    }

    static func tags(race: String?, occupation: String?, traits: [String]?, playerName: String?) -> [String] {
        let parts = [race, occupation].compactMap { $0 } + (traits ?? []).prefix(2) + [playerName].compactMap { $0 }
        return GeneratedTagRules.cleaned(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

// MARK: - Race

extension CharacterSummaryGeneration {
    /// The model's race, or Human when it wrote a common people race the sheet and portrait never
    /// name, or a class: the model sometimes makes a mage an Elf (or "Elfen") although nothing says
    /// so, or writes "Magierin" as her race, against the prompt's "Human for a person when the
    /// sheet names no race" (real example 2026-11-27).
    static func verifiedRace(_ race: String, in sheetText: String, outputLanguage: String) -> String {
        guard CharacterTermGlossary.isUnnamedCommonRace(race, in: sheetText) || CharacterTermGlossary.isClass(race) else {
            return race
        }
        return outputLanguage == "German" ? "Mensch" : "Human"
    }
}

// MARK: - Occupation

extension CharacterSummaryGeneration {
    /// The model's occupation, or, when it gave none, a class word of the name the user typed
    /// ("Aquater Kämpfer" → Kämpfer) or of the portrait tags. A class in the name counts as named (user decision
    /// 2026-11-27), but the model left it empty in every run even when told so. Only glossary
    /// class words are taken, so a name such as "Brakka Ironvein" never becomes an occupation.
    /// The portrait tags the user chose count the same way ("MAGIERIN").
    /// - Parameter race: the model's race; a class written there ("Magierin") is the occupation
    ///   when the model left that empty.
    static func occupation(_ occupation: String?, characterName: String, portraitTags: String = "", race: String = "", outputLanguage: String) -> String {
        let given = (occupation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard given.isEmpty else { return given }
        for source in [characterName, portraitTags] {
            if let term = CharacterTermGlossary.matches(in: source).first(where: { $0.kind == .characterClass }) {
                return outputLanguage == "German" ? term.german : term.english
            }
        }
        let raceWord = race.trimmingCharacters(in: .whitespacesAndNewlines)
        return CharacterTermGlossary.isClass(raceWord) ? raceWord : ""
    }
}

// MARK: - Player name

extension CharacterSummaryGeneration {
    /// The player's name the analysis keeps: only a name that really is in the analyzed text and
    /// is not the character's own name. The model is told to copy it, but it also invents one or
    /// repeats the character's name, and neither may become a tag.
    static func verifiedPlayerName(_ playerName: String?, in sheetText: String, characterName: String) -> String {
        let name = (playerName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„«»‚‘’"))
        guard name.count >= 2, name.count <= 60, sheetText.localizedStandardContains(name) else {
            return ""
        }
        let character = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !character.isEmpty, character.localizedStandardContains(name) || name.localizedStandardContains(character) {
            return ""
        }
        return name
    }
}
