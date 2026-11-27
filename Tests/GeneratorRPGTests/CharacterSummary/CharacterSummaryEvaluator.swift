// @copyright André Trettin

#if !os(tvOS)

import Foundation

@testable import GeneratorRPG

/// What a good result for one character looks like. Terms are matched case and diacritic
/// insensitive as substrings, so "dwarf" matches "Dwarven" and "fjordzwerg" matches "Fjordzwerg".
struct CharacterSummaryExpectation: Codable, Sendable, Equatable {
    /// One of these must appear in the race, e.g. ["dwarf"], ["fjordzwerg"], or the animal's or
    /// monster's name (["bear"], ["dragon"]).
    var race: [String]
    /// One of these must appear in the occupation. Empty: the sheet names no class, occupation or
    /// role, so the occupation must stay empty (never guessed).
    var occupation: [String]
    /// The player's name the sheet names; `nil`: it names none, so there is no player tag.
    var playerName: String? = nil
    /// When there are traits, at least one must contain one of these: what the values and
    /// background really show. No traits is allowed.
    var traitConcepts: [String]
    /// The description must contain one of these.
    var descriptionConcepts: [String]
    /// An invented name (unnamed character) must not contain these: it is a name, not "Goblin Skirmisher".
    var descriptiveNameTerms: [String] = []
    /// Terms that must not appear anywhere, e.g. English words when the output language is German.
    var forbiddenTerms: [String] = []
    /// Terms no trait may contain: what the sheet does not say (world knowledge about the race,
    /// "Meer") or what is not special about the character (an ordinary weapon).
    var forbiddenTraitTerms: [String] = []
}

/// The result of checking one generated `CharacterSummaryAnalysis`.
struct CharacterSummaryVerdict: Sendable, Equatable {
    let analysis: CharacterSummaryAnalysis
    /// The tag list the item stores (`CharacterSummaryAnalysis.summary`).
    let tags: [String]
    let nameRuleViolations: [String]
    let descriptionRuleViolations: [String]
    /// Format rules of race, occupation, traits and player's name, and the stored tag count.
    let tagRuleViolations: [String]
    /// Player's name present and right when the sheet names one, absent when not. Also in
    /// `tagRuleViolations`.
    let playerViolations: [String]
    let conceptViolations: [String]
    /// Share of the expected concepts found in race, occupation, traits and description, 0...1.
    let conceptScore: Double

    var ruleViolations: [String] {
        nameRuleViolations.map { "name: \($0)" }
            + descriptionRuleViolations.map { "description: \($0)" }
            + tagRuleViolations.map { "tags: \($0)" }
    }

    var violations: [String] { ruleViolations + conceptViolations }
    var passed: Bool { violations.isEmpty }
}

/// Scores one `CharacterSummaryAnalysis` against the character tag rules: 2 to 5 tags of the race
/// (always), the class or occupation (only when the sheet names one, never guessed), up to two
/// traits that are special about the character and do not repeat the race or occupation, and the
/// player's name (only when the sheet names one).
/// Pure, so the rules themselves are unit-tested without Apple Intelligence.
struct CharacterSummaryEvaluator: Sendable {
    var maximumWordsPerPart = GeneratedTagRules.maximumWordsPerTag
    var maximumCharactersPerTrait = 30
    var maximumNameWords = 4
    var maximumNameCharacters = 40
    var minimumDescriptionCharacters = 20
    var maximumDescriptionCharacters = 320
    var maximumDescriptionSentences = 2
    /// Race, occupation, up to two traits and the player's name.
    var allowedTagCount = 2...5
    var allowedTraitCount = 0...2
    /// Names that are no name.
    var genericNames: Set<String> = [
        "character", "unnamed", "unnamed character", "npc", "unknown", "monster", "name",
        "charakter", "unbenannt", "unbenannter charakter", "nsc", "unbekannt"
    ]
    /// Traits that are true of every character, so they say nothing special.
    var genericTraits: Set<String> = CharacterSummaryGeneration.genericTraitWords
    /// The description is about the character, not about the sheet the model read.
    static let formWords = ["table", "tables", "entries", "sheet", "Tabelle", "Tabellen", "Einträge", "Charakterbogen"]

    private let tagEvaluator: PdfTagEvaluator

    init() {
        var tagEvaluator = PdfTagEvaluator()
        tagEvaluator.bannedWords += Self.formWords
        self.tagEvaluator = tagEvaluator
    }

    func evaluate(
        _ analysis: CharacterSummaryAnalysis,
        existingName: String,
        expectation: CharacterSummaryExpectation
    ) -> CharacterSummaryVerdict {
        let nameViolations = nameRuleViolations(analysis.name, existingName: existingName, expectation: expectation)
        let descriptionViolations = descriptionRuleViolations(analysis, expectation: expectation)
        let playerViolations = playerViolations(analysis.playerName, expected: expectation.playerName)
        let tags = analysis.summary.tags
        var tagViolations = partRuleViolations(analysis, expectation: expectation) + playerViolations
        if !allowedTagCount.contains(tags.count) {
            tagViolations.append("\(tags.count) stored tags (\(tags.joined(separator: ", "))), allowed are \(allowedTagCount)")
        }

        var conceptViolations: [String] = []
        var scores: [Double] = []
        scores.append(match(analysis.race, expectation.race, label: "race", into: &conceptViolations))
        if !expectation.occupation.isEmpty {
            scores.append(match(analysis.occupation, expectation.occupation, label: "occupation", into: &conceptViolations))
        }
        if !analysis.traits.isEmpty {
            scores.append(match(analysis.traits.joined(separator: " | "), expectation.traitConcepts, label: "traits", into: &conceptViolations))
        }
        scores.append(match(analysis.description, expectation.descriptionConcepts, label: "description", into: &conceptViolations))

        return CharacterSummaryVerdict(
            analysis: analysis,
            tags: tags,
            nameRuleViolations: nameViolations,
            descriptionRuleViolations: descriptionViolations,
            tagRuleViolations: tagViolations,
            playerViolations: playerViolations,
            conceptViolations: conceptViolations,
            conceptScore: scores.reduce(0, +) / Double(scores.count)
        )
    }

    // MARK: - Name

    private func nameRuleViolations(_ name: String, existingName: String, expectation: CharacterSummaryExpectation) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = existingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard existing.isEmpty else {
            return PdfTagEvaluator.normalized(trimmed) == PdfTagEvaluator.normalized(existing)
                ? []
                : ["'\(trimmed)' does not keep the name '\(existing)'"]
        }
        guard !trimmed.isEmpty else { return ["is empty"] }

        var violations: [String] = []
        if trimmed.count > maximumNameCharacters {
            violations.append("is longer than \(maximumNameCharacters) characters")
        }
        if trimmed.split(whereSeparator: \.isWhitespace).count > maximumNameWords {
            violations.append("has more than \(maximumNameWords) words")
        }
        if trimmed.contains(":") || trimmed.last.map({ ".!?;".contains($0) }) == true {
            violations.append("'\(trimmed)' is no plain name")
        }
        if genericNames.contains(PdfTagEvaluator.normalized(trimmed)) {
            violations.append("'\(trimmed)' is generic")
        }
        if let term = expectation.descriptiveNameTerms.first(where: { trimmed.localizedStandardContains($0) }) {
            violations.append("'\(trimmed)' is a description ('\(term)'), not a name")
        }
        appendForbiddenTerms(expectation.forbiddenTerms, in: trimmed, to: &violations)
        return violations
    }

    // MARK: - Description

    private func descriptionRuleViolations(_ analysis: CharacterSummaryAnalysis, expectation: CharacterSummaryExpectation) -> [String] {
        let trimmed = analysis.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["is empty"] }

        var violations: [String] = []
        if trimmed.count < minimumDescriptionCharacters {
            violations.append("is shorter than \(minimumDescriptionCharacters) characters")
        }
        if trimmed.count > maximumDescriptionCharacters {
            violations.append("is longer than \(maximumDescriptionCharacters) characters")
        }
        let sentences = TableSummaryEvaluator.sentenceCount(in: trimmed)
        if sentences > maximumDescriptionSentences {
            violations.append("has \(sentences) sentences, allowed are \(maximumDescriptionSentences)")
        }
        violations.append(contentsOf: tagEvaluator.bannedWordViolations(in: trimmed))
        appendForbiddenTerms(expectation.forbiddenTerms, in: trimmed, to: &violations)
        return violations
    }

    // MARK: - Tag parts

    private func partRuleViolations(_ analysis: CharacterSummaryAnalysis, expectation: CharacterSummaryExpectation) -> [String] {
        var violations = formatViolations(of: analysis.race, label: "race", expectation: expectation)
        let occupation = analysis.occupation.trimmingCharacters(in: .whitespacesAndNewlines)
        if expectation.occupation.isEmpty {
            if !occupation.isEmpty {
                violations.append("occupation '\(occupation)' is guessed, the sheet names none")
            }
        } else {
            violations.append(contentsOf: formatViolations(of: occupation, label: "occupation", expectation: expectation))
        }

        if !allowedTraitCount.contains(analysis.traits.count) {
            violations.append("\(analysis.traits.count) traits, allowed are \(allowedTraitCount)")
        }
        let others = [analysis.race, analysis.occupation]
            .map(PdfTagEvaluator.normalized)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        for trait in analysis.traits {
            let trimmed = trait.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = PdfTagEvaluator.normalized(trimmed)
            violations.append(contentsOf: formatViolations(of: trimmed, label: "trait", expectation: expectation))
            guard !trimmed.isEmpty else { continue }
            if trimmed.count > maximumCharactersPerTrait {
                violations.append("trait '\(trimmed)' is longer than \(maximumCharactersPerTrait) characters")
            }
            if genericTraits.contains(key) {
                violations.append("trait '\(trimmed)' is generic")
            }
            if others.contains(key) {
                violations.append("trait '\(trimmed)' repeats the race or occupation")
            }
            if !seen.insert(key).inserted {
                violations.append("trait '\(trimmed)' is repeated")
            }
            for term in expectation.forbiddenTraitTerms where trimmed.localizedStandardContains(term) {
                violations.append("trait '\(trimmed)' is not on the sheet or not special ('\(term)')")
            }
        }
        return violations
    }

    private func formatViolations(of value: String, label: String, expectation: CharacterSummaryExpectation) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["\(label) is empty"] }
        var violations: [String] = []
        if trimmed.split(whereSeparator: \.isWhitespace).count > maximumWordsPerPart {
            violations.append("\(label) '\(trimmed)' has more than \(maximumWordsPerPart) words")
        }
        if trimmed.contains(":") {
            violations.append("\(label) '\(trimmed)' uses a 'label: value' form")
        }
        violations.append(contentsOf: tagEvaluator.bannedWordViolations(in: trimmed).map { "\(label) \($0)" })
        for term in expectation.forbiddenTerms where trimmed.localizedStandardContains(term) {
            violations.append("\(label) '\(trimmed)' contains forbidden term '\(term)'")
        }
        return violations
    }

    // MARK: - Player

    private func playerViolations(_ playerName: String, expected: String?) -> [String] {
        let key = PdfTagEvaluator.normalized(playerName)
        switch (expected, key.isEmpty) {
        case (nil, true):
            return []
        case (nil, false):
            return ["player '\(playerName)' is invented, the sheet names none"]
        case (.some, true):
            return ["player's name is missing although the sheet names it"]
        case (.some(let expected), false):
            return key == PdfTagEvaluator.normalized(expected) ? [] : ["player '\(playerName)' is wrong, expected '\(expected)'"]
        }
    }

    // MARK: - Helpers

    private func match(_ text: String, _ terms: [String], label: String, into violations: inout [String]) -> Double {
        guard !terms.isEmpty else { return 1 }
        if terms.contains(where: { text.localizedStandardContains($0) }) {
            return 1
        }
        violations.append("\(label) '\(text)' matches none of: \(terms.joined(separator: "|"))")
        return 0
    }

    private func appendForbiddenTerms(_ terms: [String], in text: String, to violations: inout [String]) {
        for term in terms where text.localizedStandardContains(term) {
            violations.append("contains forbidden term '\(term)'")
        }
    }
}

#endif
