// @copyright André Trettin

import Foundation

/// What a level search looks for.
public enum LevelSearchKind: String, Hashable, Sendable, CaseIterable {
    /// Adventures written for the level (their level tag or text).
    case adventure
    /// Monsters (Characters in the Monster category) whose level or challenge rating fits.
    case monster
}

/// The level part of a global search: "level 4 adventures", "monsters for level 9 characters".
/// Shown as a search token; the rest of the search text still narrows the results.
public struct LevelSearchFilter: Hashable, Identifiable, Sendable {
    public init(level: Int, kind: LevelSearchKind? = nil) {
        self.level = level
        self.kind = kind
    }

    /// The character level, 1 to `AdventurePartyFacts.maximumLevel`.
    public var level: Int
    /// `nil` looks for adventures and monsters.
    public var kind: LevelSearchKind?

    public var id: String { "\(kind?.rawValue ?? "all")-\(level)" }

    /// How far a monster's level or challenge rating may be from the searched level.
    public static let monsterTolerance = 1.0

    public func includes(_ kind: LevelSearchKind) -> Bool {
        self.kind == nil || self.kind == kind
    }

    /// An adventure matches when the levels it is written for hold the searched level.
    public func matchesAdventure(levels: ClosedRange<Int>) -> Bool {
        levels.contains(level)
    }

    /// How far `rating` is from the searched level, `nil` when it is further than
    /// `monsterTolerance`. A smaller distance is a better match.
    public func monsterDistance(rating: Double) -> Double? {
        let distance = abs(rating - Double(level))
        return distance <= Self.monsterTolerance ? distance : nil
    }
}

/// A search text read as a level search: the level, what to look for and the words left over.
/// "Give me level 4 adventures" is level 4, adventures, no text; "level 9 dragon" is level 9,
/// adventures and monsters, the text "dragon". Text without a level is no level search.
public struct LevelSearchQuery: Hashable, Sendable {
    public init(filter: LevelSearchFilter, text: String = "") {
        self.filter = filter
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var filter: LevelSearchFilter
    /// The words that are neither the level, the kind nor filler; they must match too.
    public var text: String

    public init?(parsing searchText: String) {
        let words = searchText.split { !$0.isLetter && !$0.isNumber && $0 != "/" }.map(String.init)
        let folded = words.map(Self.fold)
        guard let found = Self.firstLevel(in: folded) else { return nil }

        let wantsAdventure = folded.contains { Self.adventureWords.contains($0) }
        let wantsMonster = found.isRating || folded.contains { Self.monsterWords.contains($0) }
        let kind: LevelSearchKind? = switch (wantsAdventure, wantsMonster) {
        case (true, false): .adventure
        case (false, true): .monster
        default: nil
        }

        let remaining = words.indices.filter { index in
            let word = folded[index]
            return !found.indices.contains(index)
                && !Self.adventureWords.contains(word)
                && !Self.monsterWords.contains(word)
                && !Self.levelWords.contains(word)
                && !Self.ratingWords.contains(word)
                && !Self.fillerWords.contains(word)
        }
        self.init(
            filter: LevelSearchFilter(level: found.level, kind: kind),
            text: remaining.map { words[$0] }.joined(separator: " ")
        )
    }

    // MARK: - Monster ratings

    /// Whether a value entry of a monster holds its level or challenge rating ("Level", "CR",
    /// "Challenge Rating", "Stufe", "HG"), as typed in or imported from Foundry (`details.cr`,
    /// `details.level`).
    public static func isRatingEntryName(_ name: String) -> Bool {
        let folded = fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
        return levelWords.contains(folded) || ratingWords.contains(folded) || ratingEntryNames.contains(folded)
    }

    /// The number a level or challenge rating value starts with: "9", "1/4", "0.5", "2,5", "9 (5000 XP)".
    public static func rating(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // The lookahead keeps "100" from reading as 10.
        guard let regex = try? Regex(#"^(\d{1,2})(?:\s*/\s*(\d{1,2})|[.,](\d{1,3}))?(?!\d)"#),
              let match = trimmed.prefixMatch(of: regex),
              let whole = match.output[1].substring.flatMap({ Double($0) }) else { return nil }
        var rating = whole
        if let denominator = match.output[2].substring.flatMap({ Double($0) }) {
            guard denominator > 0 else { return nil }
            rating = whole / denominator
        } else if let fraction = match.output[3].substring {
            rating = Double("\(Int(whole)).\(fraction)") ?? whole
        }
        return rating <= Double(AdventurePartyFacts.maximumLevel) ? rating : nil
    }

    // MARK: - Parsing

    private struct FoundLevel {
        let level: Int
        let indices: Set<Int>
        /// "CR 9", "HG 9": a challenge rating, which only monsters have.
        let isRating: Bool
    }

    /// The first "level 4", "4th level", "level4", "CR 9" or "Stufe 9" in the words.
    private static func firstLevel(in words: [String]) -> FoundLevel? {
        for index in words.indices {
            let word = words[index]
            let isLevelWord = levelWords.contains(word) || ratingWords.contains(word)
            if isLevelWord, index + 1 < words.count, let level = levelNumber(words[index + 1]) {
                return FoundLevel(level: level, indices: [index, index + 1], isRating: ratingWords.contains(word))
            }
            if let (prefix, level) = attachedLevel(word) {
                return FoundLevel(level: level, indices: [index], isRating: ratingWords.contains(prefix))
            }
            if let level = levelNumber(word), index + 1 < words.count, levelWords.contains(words[index + 1]) {
                return FoundLevel(level: level, indices: [index, index + 1], isRating: false)
            }
        }
        return nil
    }

    /// "level4", "lvl4", "cr9": a level word and the number written together.
    private static func attachedLevel(_ word: String) -> (String, Int)? {
        guard let firstDigit = word.firstIndex(where: \.isNumber), firstDigit > word.startIndex else { return nil }
        let prefix = String(word[..<firstDigit])
        guard levelWords.contains(prefix) || ratingWords.contains(prefix),
              let level = levelNumber(String(word[firstDigit...])) else { return nil }
        return (prefix, level)
    }

    /// "4", "4th", "four", "vier" as a level within 1...`AdventurePartyFacts.maximumLevel`.
    private static func levelNumber(_ word: String) -> Int? {
        var digits = word
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) {
            digits.removeLast(suffix.count)
            break
        }
        let number = Int(digits) ?? numberWords[word]
        guard let number, (1...AdventurePartyFacts.maximumLevel).contains(number) else { return nil }
        return number
    }

    /// Lower case without diacritics: "Für" is "fur", "Créature" is "creature".
    private static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static let levelWords: Set<String> = [
        "level", "levels", "lvl", "lv", "stufe", "stufen", "charakterstufe", "heldenstufe", "erfahrungsstufe",
        "niveau", "niveaux", "nivel", "livello", "poziom", "poziomu"
    ]

    /// Words for a challenge rating, which only monsters have.
    private static let ratingWords: Set<String> = [
        "cr", "hg", "challenge", "rating", "herausforderungsgrad"
    ]

    /// Entry names that hold a rating only as a whole phrase.
    private static let ratingEntryNames: Set<String> = [
        "challenge rating", "challengerating", "challenge level"
    ]

    private static let adventureWords: Set<String> = [
        "adventure", "adventures", "scenario", "scenarios", "campaign", "campaigns", "oneshot", "oneshots",
        "abenteuer", "szenario", "szenarien", "kampagne", "kampagnen",
        "aventure", "aventures", "campagne", "campagnes", "aventura", "aventuras", "escenario", "escenarios",
        "avventura", "avventure", "avontuur", "avonturen", "przygoda", "przygody"
    ]

    private static let monsterWords: Set<String> = [
        "monster", "monsters", "creature", "creatures", "enemy", "enemies", "foe", "foes", "opponent", "opponents",
        "beast", "beasts", "kreatur", "kreaturen", "gegner", "ungeheuer", "bestie", "bestien",
        "monstre", "monstres", "monstruo", "monstruos", "criatura", "criaturas", "mostro", "mostri", "creatura",
        "potwor", "potwory"
    ]

    /// Words a spoken request wraps around the search ("Give me … for level 9 characters"), in
    /// English and German, and the party nouns ("characters", "Helden").
    private static let fillerWords: Set<String> = [
        "give", "me", "show", "find", "search", "look", "looking", "get", "list", "any", "some", "all", "a", "an",
        "the", "for", "of", "with", "in", "i", "need", "want", "would", "like", "please", "are", "there", "is",
        "do", "does", "have", "has", "we", "you", "my", "our", "what", "which", "good", "suitable", "appropriate",
        "fitting", "matching", "that", "to", "can", "could", "something", "anything", "and", "or",
        "character", "characters", "player", "players", "pc", "pcs", "party", "group", "hero", "heroes",
        "adventurer", "adventurers",
        "gib", "gibt", "gibts", "es", "mir", "zeig", "zeige", "zeigen", "finde", "finden", "such", "suche",
        "suchen", "alle", "irgendein", "irgendeine", "irgendeinen", "irgendwelche", "ein", "eine", "einen",
        "einem", "einer", "der", "die", "das", "den", "dem", "des", "fur", "mit", "von", "im", "ich", "brauche",
        "mochte", "bitte", "welche", "passend", "passende", "passenden", "passendes", "etwas", "was", "wir", "du",
        "haben", "habe", "hast", "charakter", "charaktere", "charakteren", "spieler", "spielerinnen", "helden",
        "gruppe", "sc", "scs", "ab", "und", "oder"
    ]

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        // "elf" (11) is left out: "elf level 5" names an elf, not level 11.
        "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "funf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
        "zehn": 10, "zwolf": 12
    ]
}

public extension AdventurePartyFacts {
    /// The levels an adventure is written for: a level tag first (the band the extraction writes,
    /// "1-4", or "Level 3"), else the first level its name or description names.
    static func adventureLevels(tags: [String], name: String, description: String) -> ClosedRange<Int>? {
        for tag in tags {
            if let levels = levels(inTag: tag) { return levels }
        }
        return AdventurePartyFacts(text: "\(name)\n\(description)").levels
    }
}
