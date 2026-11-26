// @copyright André Trettin

import Foundation
import FoundationModels

/// Structured extraction result for a character sheet. The tags are generated as separate parts,
/// so each one has its rule: race, class or occupation, sex (only when the sheet shows it) and two
/// traits that are special about this character. `summary` joins them into the title,
/// description and tag list the item stores.
@Generable(description: "Extracted name, description and tag parts of a role-playing game character")
public struct CharacterSummaryAnalysis: Equatable, Sendable, Codable {

    @Guide(
        description: """
        The character's name, written as a name, never as a description. When the sheet starts \
        with a name, it is exactly that name. Otherwise an invented personal name that fits the \
        race, sex and world. No label, no period.
        """
    )
    public var name: String

    @Guide(
        description: """
        One or two sentences in the output language about who the character is: race, class or \
        occupation and what makes them special. Write about the character, never about entries, \
        values, a sheet or a table. Do not use the words \(GeneratedTagRules.bannedWordsText).
        """
    )
    public var description: String

    @Guide(
        description: """
        The character's race, species or people in 1 to 3 words. A name that only exists in the \
        game's own world stays unchanged, for example "Fjordzwerg" or "Kaiter"; a common race is \
        written in the output language. Human when the sheet names none.
        """
    )
    public var race: String

    @Guide(
        description: """
        The character's class or occupation in 1 to 3 words, as the sheet names it, in the output \
        language. Only a monster without one gets its role in a fight.
        """
    )
    public var occupation: String

    @Guide(
        description: """
        Male or Female, written in the output language, only when a pronoun, a gendered word for \
        a person, a clearly male or female first name, or the portrait shows it. An empty text \
        when nothing shows it, as for most monsters. Never guess.
        """
    )
    public var sex: String

    @Guide(
        description: """
        Exactly two short tags of 1 to 3 words, in the output language, for what is special about \
        this character, read from the sheet: values clearly higher than the others, the \
        background, the weapon or special abilities. A low or average value is no trait. Not the \
        race, occupation or sex again, no label, and no generic word such as Character, Stats or \
        Attributes.
        """,
        .count(2)
    )
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
