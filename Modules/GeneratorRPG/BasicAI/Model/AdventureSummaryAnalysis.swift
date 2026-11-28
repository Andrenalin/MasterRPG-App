// @copyright André Trettin

import Foundation
import FoundationModels

/// What the heroes mainly do in an adventure. It is the first content tag of an adventure, written
/// in the output language by `name(in:)`, so adventures can be sorted by their type (all rescues,
/// all investigations) in any language. Ghosts, temples or cults are free tags, not types.
@Generable(description: "What the heroes mainly do in the adventure")
enum AdventurePlotKind: String, CaseIterable, Sendable, Equatable {
    case dungeon
    case investigation
    case travel
    case rescue
    case guarding
    case heist
    case hunt
    case exploration
    case intrigue
    case battle
    case survival
    case escape

    /// What each type covers, for the model's instructions: one line per type.
    static var instructionList: String {
        allCases.map { "- \($0.rawValue): \($0.covers)" }.joined(separator: "\n")
    }

    private var covers: String {
        switch self {
        case .dungeon: "most scenes explore the rooms of one dangerous place such as a dungeon, cave or tomb"
        case .investigation: "solving a mystery, a crime, a haunting or a curse by finding clues and questioning people, even when the clues lead to a ruin or a crypt in the end"
        case .travel: "a journey from one place to another, with its stops and the dangers on the way"
        case .rescue: "freeing or saving prisoners, hostages, missing or trapped people"
        case .guarding: "protecting, escorting or guarding a person, a caravan, a place or an item"
        case .heist: "stealing something: a robbery, a break-in or an infiltration"
        case .hunt: "tracking down and defeating a monster, a beast or a wanted person"
        case .exploration: "discovering an unknown land, island, planet or wilderness"
        case .intrigue: "politics, negotiation, social conflict or betrayal at a court, in a city or a guild"
        case .battle: "a war, a siege, the defense of a place or a large fight"
        case .survival: "surviving a disaster, a storm, the wilderness or being stranded"
        case .escape: "the heroes themselves are captured or trapped and must break out or flee"
        }
    }

    /// The tag of the type in `outputLanguage` (the English name of an `OutputLanguage`), English
    /// for a language without its own names.
    func name(in outputLanguage: String) -> String {
        let names = Self.names[self] ?? []
        let index = MapPlaceKind.languages.firstIndex(of: outputLanguage) ?? 0
        return names.indices.contains(index) ? names[index] : rawValue.capitalized
    }

    /// In the order of `MapPlaceKind.languages`.
    private static let names: [AdventurePlotKind: [String]] = [
        .dungeon: ["Dungeon", "Dungeon", "Donjon", "Mazmorra", "Sotterraneo", "Masmorra", "Kerker", "Loch", "ダンジョン"],
        .investigation: ["Investigation", "Ermittlung", "Enquête", "Investigación", "Indagine", "Investigação", "Onderzoek", "Śledztwo", "調査"],
        .travel: ["Travel", "Reise", "Voyage", "Viaje", "Viaggio", "Viagem", "Reis", "Podróż", "旅"],
        .rescue: ["Rescue", "Rettung", "Sauvetage", "Rescate", "Salvataggio", "Resgate", "Redding", "Ratunek", "救出"],
        .guarding: ["Guarding", "Bewachung", "Protection", "Protección", "Protezione", "Proteção", "Bewaking", "Ochrona", "護衛"],
        .heist: ["Heist", "Raubzug", "Casse", "Atraco", "Colpo", "Assalto", "Kraak", "Skok", "強盗"],
        .hunt: ["Hunt", "Jagd", "Chasse", "Cacería", "Caccia", "Caçada", "Jacht", "Polowanie", "狩り"],
        .exploration: ["Exploration", "Erkundung", "Exploration", "Exploración", "Esplorazione", "Exploração", "Verkenning", "Eksploracja", "探索"],
        .intrigue: ["Intrigue", "Intrige", "Intrigue", "Intriga", "Intrigo", "Intriga", "Intrige", "Intryga", "陰謀"],
        .battle: ["Battle", "Schlacht", "Bataille", "Batalla", "Battaglia", "Batalha", "Veldslag", "Bitwa", "戦い"],
        .survival: ["Survival", "Überleben", "Survie", "Supervivencia", "Sopravvivenza", "Sobrevivência", "Overleven", "Przetrwanie", "サバイバル"],
        .escape: ["Escape", "Flucht", "Évasion", "Huida", "Fuga", "Fuga", "Ontsnapping", "Ucieczka", "脱出"]
    ]
}

/// The character level and the number of player characters an adventure is written for, read from
/// its text in code: the on-device model invents both when the text names neither, and writes them
/// in a different form every time. Both are left out when the text does not name them.
struct AdventurePartyFacts: Equatable, Sendable {
    /// The lowest and highest character level the text names, e.g. 3...5 for "levels 3-5".
    var levels: ClosedRange<Int>?
    /// The smallest and largest number of player characters, e.g. 3...5 for "3 to 5 characters".
    var characters: ClosedRange<Int>?

    /// Levels above this are no character levels (page numbers, years).
    static let maximumLevel = 30
    /// Counts above this are no group sizes.
    static let maximumCharacters = 10
    /// The width of a level band: 1-4, 5-8, 9-12, …
    static let bandWidth = 4

    init(levels: ClosedRange<Int>? = nil, characters: ClosedRange<Int>? = nil) {
        self.levels = levels
        self.characters = characters
    }

    /// Reads the first level and the first character count `text` names.
    init(text: String) {
        let prepared = Self.prepared(text)
        levels = Self.firstLevels(in: prepared)
        characters = Self.firstCharacters(in: prepared)
    }

    /// The level band, "1-4", "5-8", …: the band that holds the middle of the named levels, so
    /// "levels 3-5" is "1-4" and "levels 4-6" is "5-8".
    var levelBand: String? {
        guard let levels else { return nil }
        let middle = (levels.lowerBound + levels.upperBound) / 2
        let start = (middle - 1) / Self.bandWidth * Self.bandWidth + 1
        return "\(start)-\(start + Self.bandWidth - 1)"
    }

    /// "3-5 PC", "4 SC": the count as the text names it, with the output language's abbreviation
    /// for a player character.
    func characterTag(in outputLanguage: String) -> String? {
        guard let characters else { return nil }
        let count = characters.lowerBound == characters.upperBound
            ? "\(characters.lowerBound)"
            : "\(characters.lowerBound)-\(characters.upperBound)"
        return "\(count) \(Self.playerCharacterAbbreviation(in: outputLanguage))"
    }

    /// The tags in their order: the level band, then the character count.
    func tags(in outputLanguage: String) -> [String] {
        [levelBand, characterTag(in: outputLanguage)].compactMap(\.self)
    }

    /// "PC" in English, "SC" (Spielercharakter) in German, "PJ" in French, …
    static func playerCharacterAbbreviation(in outputLanguage: String) -> String {
        let abbreviations = ["PC", "SC", "PJ", "PJ", "PG", "PJ", "PC", "BG", "PC"]
        let index = MapPlaceKind.languages.firstIndex(of: outputLanguage) ?? 0
        return abbreviations.indices.contains(index) ? abbreviations[index] : abbreviations[0]
    }

    /// Whether a model tag is a level or a character count, which code writes instead.
    static func isPartyTag(_ tag: String) -> Bool {
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

    private static func firstLevels(in text: String) -> ClosedRange<Int>? {
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
                let accepted = high != nil || hasColon || unambiguousLevelWords.contains(word)
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
                let accepted = hasCharacterWordAfter(match.range.upperBound, in: text)
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

/// What the model writes for an adventure. The level and the character count are not generated:
/// `AdventurePartyFacts` reads them from the text. The summary comes before the title: written
/// after an output-language summary, the title of a German adventure in English output is
/// translated instead of copied. The type comes before the tags, so a tag does not repeat it.
@Generable(description: "Extracted title, short summary, type and tags of a role-playing game adventure")
struct AdventureSummaryGeneration: Equatable, Sendable {

    @Guide(
        description: """
        A short summary of the adventure in two or three short sentences, at most 60 words, in \
        the output language: who sends the heroes or what draws them in, what they must do and \
        where, and the main threat or twist. Never the character level or the number of players. Never call it a table, \
        entries or a list. Do not use the words \(GeneratedTagRules.bannedWordsText).
        """
    )
    var description: String

    @Guide(
        description: """
        A title of 2 to 6 words in the output language: the adventure's own name when it has one, \
        otherwise what the adventure is about, in the same language as the summary. No sentence, no period, no label before it. Never \
        the words adventure, scenario, module or chapter.
        """
    )
    var title: String

    @Guide(description: "What the heroes do in most scenes of this adventure, not where it takes place")
    var kind: AdventurePlotKind

    @Guide(
        description: GeneratedTagRules.guideDescription(
            contents: """
            Not the type of adventure. They name what is special in this adventure: its places, \
            creatures, villains, factions, items or themes, and the genre. Never a character \
            level, a number of characters or players, and never the words adventure or scenario.
            """,
            extraGenericTags: AdventureSummaryGeneration.genericTags
        ),
        .count(AdventureSummaryGeneration.contentTagRange)
    )
    var tags: [String]

    /// The content tags; the type tag makes the total `GeneratedTagRules.countRange`. The level and
    /// count tags come on top and push the last content tags out (`GeneratedTagRules.cleaned`).
    static let contentTagRange = (GeneratedTagRules.countRange.lowerBound - 1)...(GeneratedTagRules.countRange.upperBound - 1)

    /// Words that name the form of an adventure, not its content.
    static let genericTags = ["Adventure", "Scenario", "Module", "Chapter", "Campaign"]

    /// Whole words that call an adventure an adventure, in the output languages. A title loses a
    /// leading label ("Adventure: …") and a trailing one ("Lighthouse Adventure"); a tag that
    /// is one is dropped.
    static let formWords: Set<String> = [
        "adventure", "adventures", "scenario", "module", "chapter", "campaign", "oneshot", "one-shot",
        "abenteuer", "szenario", "kampagne", "kapitel",
        "aventure", "scénario", "campagne", "aventura", "escenario", "campaña", "avventura",
        "campagna", "avontuur", "przygoda", "scenariusz", "kampania"
    ]

    /// The title as it is stored: without a leading form label or a trailing form word; the type's
    /// name when nothing else is left.
    static func cleanedTitle(_ title: String, kind: AdventurePlotKind?, outputLanguage: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.firstIndex(of: ":"), isFormPhrase(String(trimmed[..<colon])) {
            trimmed = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.count > 1, let last = words.last, isFormWord(last) {
            words.removeLast()
        }
        if words.count == 1, let only = words.first, isFormWord(only) {
            words.removeAll()
        }
        let cleaned = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".:-–—,;").union(.whitespaces))
        guard cleaned.isEmpty, let kind else { return cleaned }
        return kind.name(in: outputLanguage)
    }

    /// The level band and the character count first, then the type, then the content tags without
    /// form words, party tags, the title and the type in another language, cleaned like every
    /// generated tag list.
    static func tags(
        facts: AdventurePartyFacts,
        kind: AdventurePlotKind?,
        contentTags: [String]?,
        title: String,
        outputLanguage: String
    ) -> [String] {
        let titleKey = normalized(title)
        let kindKeys = Set((kind.map { kind in MapPlaceKind.languages.map { kind.name(in: $0) } } ?? []).map(normalized))
        let content = (contentTags ?? [])
            .map { GeneratedTagRules.withoutLabel($0).trimmingCharacters(in: CharacterSet(charactersIn: ".;").union(.whitespaces)) }
            .filter { tag in
                let key = normalized(tag)
                return !key.isEmpty && key != titleKey && !kindKeys.contains(key)
                    && !isFormPhrase(tag) && !AdventurePartyFacts.isPartyTag(tag)
            }
        return GeneratedTagRules.cleaned(
            facts.tags(in: outputLanguage) + (kind.map { [$0.name(in: outputLanguage)] } ?? []) + content
        )
    }

    /// Every word of `text` is a form word: "Adventure", "One-Shot Abenteuer".
    private static func isFormPhrase(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace }.map(String.init)
        return !words.isEmpty && words.allSatisfy(isFormWord)
    }

    private static func isFormWord(_ word: String) -> Bool {
        let key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return formWords.contains(key)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }
}

extension TableSummaryAnalysisProgress {
    /// An adventure's progress: the cleaned title, and the tags once the type is known.
    init(_ partial: AdventureSummaryGeneration.PartiallyGenerated, facts: AdventurePartyFacts, outputLanguage: String) {
        let title = partial.title.map { AdventureSummaryGeneration.cleanedTitle($0, kind: nil, outputLanguage: outputLanguage) }
        let tags = partial.kind == nil ? [] : AdventureSummaryGeneration.tags(
            facts: facts,
            kind: partial.kind,
            contentTags: partial.tags,
            title: title ?? "",
            outputLanguage: outputLanguage
        )
        self.title = title
        self.description = partial.description
        self.tags = tags.isEmpty ? nil : tags
    }
}
