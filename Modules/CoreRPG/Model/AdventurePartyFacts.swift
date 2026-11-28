// @copyright André Trettin

import Foundation

/// The character level and the number of player characters an adventure is written for, read from
/// its text in code: the on-device model invents both when the text names neither, and writes them
/// in a different form every time. Both are left out when the text does not name them.
///
/// Lives in CoreRPG because the Adventure "Extract Information" (GeneratorRPG) writes the level band
/// tag with it and the global level search (`LevelSearchQuery`) reads an adventure's level with it.
public struct AdventurePartyFacts: Equatable, Sendable {
    /// The lowest and highest character level the text names, e.g. 3...5 for "levels 3-5".
    public var levels: ClosedRange<Int>?
    /// The smallest and largest number of player characters, e.g. 3...5 for "3 to 5 characters".
    public var characters: ClosedRange<Int>?

    /// Levels above this are no character levels (page numbers, years).
    public static let maximumLevel = 30
    /// Counts above this are no group sizes.
    public static let maximumCharacters = 10
    /// The width of a level band: 1-4, 5-8, 9-12, …
    public static let bandWidth = 4

    public init(levels: ClosedRange<Int>? = nil, characters: ClosedRange<Int>? = nil) {
        self.levels = levels
        self.characters = characters
    }

    /// Reads the first level and the first character count `text` names.
    public init(text: String) {
        let prepared = Self.prepared(text)
        levels = Self.firstLevels(in: prepared)
        characters = Self.firstCharacters(in: prepared)
    }

    /// The level band, "1-4", "5-8", …: the band that holds the middle of the named levels, so
    /// "levels 3-5" is "1-4" and "levels 4-6" is "5-8".
    public var levelBand: String? {
        guard let levels else { return nil }
        let middle = (levels.lowerBound + levels.upperBound) / 2
        let start = (middle - 1) / Self.bandWidth * Self.bandWidth + 1
        return "\(start)-\(start + Self.bandWidth - 1)"
    }

    /// The levels a tag names: the band the extraction writes ("1-4") or a level phrase ("Level 4",
    /// "Stufe 3-5", "5th level"). A tag holds nothing else, so a level word alone is enough here,
    /// unlike in running text, where "level 2" may be a floor.
    public static func levels(inTag tag: String) -> ClosedRange<Int>? {
        let prepared = prepared(tag)
        if let band = try? Regex(#"^\s*(\d{1,2})\s*-\s*(\d{1,2})\s*$"#),
           let match = prepared.wholeMatch(of: band),
           let low = number(match.output[1].substring) {
            return levelRange(low, number(match.output[2].substring))
        }
        return firstLevels(in: prepared, requiresContext: false)
    }

    /// Whether a model tag is a level or a character count, which code writes instead.
    public static func isPartyTag(_ tag: String) -> Bool {
        let facts = AdventurePartyFacts(text: tag)
        if facts.levels != nil || facts.characters != nil {
            return true
        }
        let words = prepared(tag).split { !$0.isLetter }.map(String.init)
        return words.contains { partyTagWords.contains($0) }
    }

    // MARK: - Parsing

    /// Words that make a tag a level or count tag, in the output languages.
    private static let partyTagWords: Set<String> = [
        "level", "levels", "lvl", "stufe", "stufen", "niveau", "nivel", "livello", "poziom",
        "pc", "pcs", "sc", "scs", "pj", "pjs", "pg", "bg", "players", "spieler"
    ]

    /// German level words that never mean a floor ("Ebene" is the floor).
    private static let unambiguousLevelWords: Set<String> = [
        "stufe", "stufen", "charakterstufe", "charakterstufen", "erfahrungsstufe", "erfahrungsgrad", "heldenstufe"
    ]

    /// Lower case, number words as digits, every dash a hyphen-minus.
    private static func prepared(_ text: String) -> String {
        let dashes: ClosedRange<Character> = "\u{2010}"..."\u{2015}"
        var result = String(text.lowercased().map { dashes.contains($0) || $0 == "\u{2212}" ? "-" : $0 })
        for (word, digit) in numberWords {
            if let regex = try? Regex("\\b\(word)\\b") {
                result = result.replacing(regex, with: "\(digit)")
            }
        }
        return result
    }

    /// Whole-word number words up to ten. "ein"/"a"/"un" are left out: they are articles far
    /// more often than counts.
    private static let numberWords: [(String, Int)] = [
        ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10),
        ("eins", 1), ("zwei", 2), ("drei", 3), ("vier", 4), ("fünf", 5), ("sechs", 6), ("sieben", 7), ("acht", 8), ("neun", 9), ("zehn", 10)
    ]

    private static let rangeSeparator = #"\s*(?:-|to|bis|und|and|or|oder|à|a|al|o)\s*"#
    private static let levelWord = #"level|levels|lvl|stufe|stufen|charakterstufen?|erfahrungsstufe|erfahrungsgrad|heldenstufe|niveau|niveaux|nivel|niveles|livello|livelli"#
    private static let characterWord = #"player characters?|characters?|pcs?|players?|heroes|adventurers|party|spielercharaktere(?:n)?|spielerfiguren|charaktere(?:n)?|spieler(?:innen)?|helden|abenteurer(?:innen)?|scs?|pjs?|pgs?|personnages|joueurs|jugadores|personajes|giocatori|personaggi"#
    /// Nouns that name a player character without any doubt: a bare "4 players" is a count.
    private static let unambiguousCharacterWords: Set<String> = [
        "pc", "pcs", "sc", "scs", "pj", "pjs", "pg", "pgs", "player character", "player characters",
        "spielercharaktere", "spielercharakteren", "players", "player", "spieler", "spielerinnen", "joueurs", "jugadores", "giocatori"
    ]

    /// `requiresContext`: a match needs a range, a colon, an unambiguous word, a "for" before it or
    /// a character noun after it, so "the 2nd level of the tower" is no character level.
    private static func firstLevels(in text: String, requiresContext: Bool = true) -> ClosedRange<Int>? {
        // "level 3", "levels 3-5", "Stufe 1 bis 4", "niveau 5"
        let wordFirst = try? Regex("\\b(\(levelWord))\\s*(:)?\\s*(\\d{1,2})\\.?(?:\(rangeSeparator)(\\d{1,2})\\b)?")
        // "3rd-level", "1st to 4th level", "3.-5. Stufe", "5th level characters"
        let numberFirst = try? Regex("\\b(\\d{1,2})(st|nd|rd|th|\\.)?(?:\(rangeSeparator)(\\d{1,2})(?:st|nd|rd|th|\\.)?)?[\\s-]*(\(levelWord))\\b")
        var candidates: [(position: String.Index, range: ClosedRange<Int>)] = []

        if let wordFirst {
            for match in text.matches(of: wordFirst) {
                let word = String(match.output[1].substring ?? "")
                let hasColon = match.output[2].substring != nil
                guard let low = number(match.output[3].substring) else { continue }
                let high = number(match.output[4].substring)
                let accepted = !requiresContext || high != nil || hasColon || unambiguousLevelWords.contains(word)
                    || hasForBefore(match.range.lowerBound, in: text)
                    || hasCharacterWordAfter(match.range.upperBound, in: text)
                if accepted, let range = levelRange(low, high) {
                    candidates.append((match.range.lowerBound, range))
                }
            }
        }
        if let numberFirst {
            for match in text.matches(of: numberFirst) {
                let word = String(match.output[4].substring ?? "")
                guard let low = number(match.output[1].substring) else { continue }
                let high = number(match.output[3].substring)
                let isOrdinal = match.output[2].substring != nil
                // "the 2nd level of the tower" is a floor; "a 2nd-level party" and "der 9. Stufe" are not.
                let accepted = !requiresContext || hasCharacterWordAfter(match.range.upperBound, in: text)
                    || unambiguousLevelWords.contains(word)
                    || (isOrdinal && hasForBefore(match.range.lowerBound, in: text))
                if accepted, let range = levelRange(low, high) {
                    candidates.append((match.range.lowerBound, range))
                }
            }
        }
        return candidates.min { $0.position < $1.position }?.range
    }

    private static func firstCharacters(in text: String) -> ClosedRange<Int>? {
        // "3-5 characters", "4 PCs", "für 3 bis 5 Helden", "a party of 4"
        guard let countFirst = try? Regex("\\b(\\d{1,2})(?:\(rangeSeparator)(\\d{1,2}))?\\s*(\(characterWord))\\b"),
              let partyOf = try? Regex("\\b(?:party|group|gruppe|groupe|grupo|gruppo)\\s+(?:of|von|de|di)\\s+(\\d{1,2})(?:\(rangeSeparator)(\\d{1,2}))?\\b")
        else { return nil }
        var candidates: [(position: String.Index, range: ClosedRange<Int>)] = []
        for match in text.matches(of: countFirst) {
            let noun = String(match.output[3].substring ?? "")
            guard noun != "party", let low = number(match.output[1].substring) else { continue }
            let high = number(match.output[2].substring)
            let accepted = high != nil || unambiguousCharacterWords.contains(noun)
                || hasForBefore(match.range.lowerBound, in: text)
            if accepted, let range = characterRange(low, high) {
                candidates.append((match.range.lowerBound, range))
            }
        }
        for match in text.matches(of: partyOf) {
            guard let low = number(match.output[1].substring) else { continue }
            if let range = characterRange(low, number(match.output[2].substring)) {
                candidates.append((match.range.lowerBound, range))
            }
        }
        return candidates.min { $0.position < $1.position }?.range
    }

    private static func number(_ text: Substring?) -> Int? {
        text.flatMap { Int($0) }
    }

    private static func levelRange(_ low: Int, _ high: Int?) -> ClosedRange<Int>? {
        ordered(low, high ?? low, within: 1...maximumLevel)
    }

    private static func characterRange(_ low: Int, _ high: Int?) -> ClosedRange<Int>? {
        ordered(low, high ?? low, within: 1...maximumCharacters)
    }

    private static func ordered(_ first: Int, _ second: Int, within bounds: ClosedRange<Int>) -> ClosedRange<Int>? {
        let range = min(first, second)...max(first, second)
        return bounds.contains(range.lowerBound) && bounds.contains(range.upperBound) ? range : nil
    }

    /// "for", "für", "pour", "para", "per" or "ab" right before the match.
    private static func hasForBefore(_ index: String.Index, in text: String) -> Bool {
        lastWord(before: index, in: text).map { ["for", "für", "fur", "pour", "para", "per", "ab", "from", "von"].contains($0) } ?? false
    }

    /// A character noun within a few words after the match: "level 3 characters", "Stufe 5 für 4 Spieler".
    private static func hasCharacterWordAfter(_ index: String.Index, in text: String) -> Bool {
        let following = text[index...].prefix(32)
        guard let regex = try? Regex("\\b(\(characterWord))\\b") else { return false }
        return following.contains(regex)
    }

    private static func lastWord(before index: String.Index, in text: String) -> String? {
        let preceding = text[..<index].suffix(12)
        return preceding.split { !$0.isLetter }.last.map(String.init)
    }
}
