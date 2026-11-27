// @copyright André Trettin

import Foundation

/// German class and race names with their English game term, for a German sheet analyzed into
/// another language. The on-device model translates such words literally ("Waldläuferin" →
/// "Woodrunner" instead of Ranger), so the analyzer adds one line per word that is really on
/// the sheet. Only matched words go into the prompt: the model copies examples it is shown, so a
/// fixed list of examples would turn unrelated characters into rangers or dwarves.
enum CharacterTermGlossary {
    struct Term: Sendable, Equatable {
        enum Kind: Sendable { case characterClass, race }

        /// The word as it appears on a German sheet.
        let german: String
        /// The English game term; the model writes it in the output language.
        let english: String
        let kind: Kind
        /// A female form ("Waldläuferin"): a gendered word for a person, so it also shows the sex.
        let isFemaleForm: Bool
    }

    /// Male and female form per class; the female form is left out when it is the same word.
    static let terms: [Term] = classes.flatMap { german, female, english in
        [Term(german: german, english: english, kind: .characterClass, isFemaleForm: false)]
            + (female.map { [Term(german: $0, english: english, kind: .characterClass, isFemaleForm: true)] } ?? [])
    } + races.map { Term(german: $0.german, english: $0.english, kind: .race, isFemaleForm: false) }

    /// German D&D-style class and common occupation names: (male form, female form, English).
    private static let classes: [(String, String?, String)] = [
        ("Waldläufer", "Waldläuferin", "Ranger"),
        ("Krieger", "Kriegerin", "Fighter"),
        ("Kämpfer", "Kämpferin", "Fighter"),
        ("Magier", "Magierin", "Wizard"),
        ("Zauberer", "Zauberin", "Sorcerer"),
        ("Hexenmeister", "Hexenmeisterin", "Warlock"),
        ("Schurke", "Schurkin", "Rogue"),
        ("Dieb", "Diebin", "Thief"),
        ("Kleriker", "Klerikerin", "Cleric"),
        ("Priester", "Priesterin", "Priest"),
        ("Druide", "Druidin", "Druid"),
        ("Mönch", "Nonne", "Monk"),
        ("Barde", "Bardin", "Bard"),
        ("Barbar", "Barbarin", "Barbarian"),
        ("Paladin", "Paladinin", "Paladin"),
        ("Jäger", "Jägerin", "Hunter"),
        ("Heiler", "Heilerin", "Healer"),
        ("Söldner", "Söldnerin", "Mercenary"),
        ("Schmied", "Schmiedin", "Blacksmith"),
        ("Händler", "Händlerin", "Merchant"),
        ("Wirt", "Wirtin", "Innkeeper"),
        ("Arzt", "Ärztin", "Doctor"),
        ("Walfänger", "Walfängerin", "Whaler")
    ]

    /// Common German race names that differ from the English term. World-specific names such as
    /// "Fjordzwerg" are whole words of their own and do not match "Zwerg", so they stay unchanged.
    /// "Elf" is left out: in German it is also the number eleven.
    private static let races: [(german: String, english: String)] = [
        ("Mensch", "Human"),
        ("Elfe", "Elf"),
        ("Zwerg", "Dwarf"),
        ("Zwergin", "Dwarf"),
        ("Halbling", "Halfling"),
        ("Gnom", "Gnome"),
        ("Ork", "Orc"),
        ("Halbork", "Half-Orc"),
        ("Halbelf", "Half-Elf"),
        ("Drachengeborener", "Dragonborn"),
        ("Drachengeborene", "Dragonborn"),
        ("Riese", "Giant"),
        ("Echsenmensch", "Lizardfolk")
    ]

    /// The terms whose German word is a whole word of `text`, case insensitive, each once.
    static func matches(in text: String) -> [Term] {
        let words = Set(text.split { !$0.isLetter }.map { $0.lowercased() })
        return terms.filter { words.contains($0.german.lowercased()) }
    }

    /// The prompt lines for the matched words, empty when the output is German (the words are
    /// already right) or nothing matches.
    static func hints(in text: String, outputLanguage: String) -> [String] {
        guard outputLanguage != "German" else { return [] }
        return matches(in: text).map { term in
            switch term.kind {
            case .characterClass where term.isFemaleForm:
                "\"\(term.german)\" is the female form of the class \(term.english)."
            case .characterClass:
                "\"\(term.german)\" is the class \(term.english)."
            case .race:
                "\"\(term.german)\" is the race \(term.english)."
            }
        }
    }
}
