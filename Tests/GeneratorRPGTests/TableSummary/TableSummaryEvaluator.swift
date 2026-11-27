// @copyright André Trettin

#if !os(tvOS)

import Foundation
import NaturalLanguage

@testable import GeneratorRPG

/// What a good title, description and tag set for one table look like. Content expectations are
/// *concept groups* as in `PdfTagExpectation`: a group is matched when any of its terms appears in
/// the text, so "forest" and "Wald" can stand for the same idea.
struct TableSummaryExpectation: Codable, Sendable, Equatable {
    /// Concepts and group count for the tags. Its own `forbiddenTerms` stay empty; use `forbiddenTerms` below.
    var tags: PdfTagExpectation
    /// At least one of these concepts must appear in the title.
    var titleConcepts: [[String]]
    /// At least one of these concepts must appear in the description.
    var descriptionConcepts: [[String]]
    /// Terms that must not appear in the title, description or any tag, e.g. English words when
    /// the output language is German.
    var forbiddenTerms: [String] = []
}

/// The result of checking one generated `TableSummaryAnalysis` against the rules and the expectation.
struct TableSummaryVerdict: Sendable, Equatable {
    let title: String
    let description: String
    let tags: [String]
    /// Rule violations of the title, without the concept check.
    let titleRuleViolations: [String]
    let descriptionRuleViolations: [String]
    /// Rule violations of the tags, without the concept check.
    let tagRuleViolations: [String]
    /// Missing expected concepts in title, description and tags.
    let conceptViolations: [String]
    /// Share of the required concepts that were found, 0...1.
    let conceptScore: Double

    var ruleViolations: [String] {
        titleRuleViolations.map { "title: \($0)" }
            + descriptionRuleViolations.map { "description: \($0)" }
            + tagRuleViolations.map { "tags: \($0)" }
    }

    var violations: [String] { ruleViolations + conceptViolations }
    var rulesPassed: Bool { ruleViolations.isEmpty }
    var passed: Bool { violations.isEmpty }
}

/// Scores one `TableSummaryAnalysis`. Pure, so the rules themselves are unit-tested without Apple
/// Intelligence. The tag rules are the ones of the PDF and photo evaluation (`PdfTagEvaluator`,
/// which reads `GeneratedTagRules`) plus table specific generic words; the description is checked
/// for the same banned words.
struct TableSummaryEvaluator: Sendable {
    var tagEvaluator: PdfTagEvaluator
    var maximumTitleWords = 8
    var maximumTitleCharacters = 60
    var minimumDescriptionCharacters = 20
    var maximumDescriptionCharacters = 320
    /// Mirrors "A 1–2 sentence description" in `TableSummaryAnalysis.description`.
    var maximumDescriptionSentences = 2
    /// Whole words a description must not call the item, e.g. "table" for a map or an adventure,
    /// which reuse the table analysis. Empty for tables.
    var misnamingWords: [String] = []
    /// Titles that say nothing about this table. The label form "Table: ..." is caught by the same list.
    var genericTitles: Set<String> = [
        "table", "tables", "random table", "rpg table", "table entries", "entries", "untitled", "title",
        "tabelle", "zufallstabelle", "rollenspieltabelle", "eintrage", "titel", "ohne titel"
    ]

    init() {
        var tagEvaluator = PdfTagEvaluator()
        // Words that describe the form, not the content. They are true of every table.
        tagEvaluator.genericTags.formUnion([
            "table", "tables", "random table", "roll table", "rpg table", "entries", "list", "d&d",
            "tabelle", "tabellen", "zufallstabelle", "eintrage", "liste"
        ])
        self.tagEvaluator = tagEvaluator
    }

    func evaluate(
        title: String,
        description: String,
        tags: [String],
        expectation: TableSummaryExpectation
    ) -> TableSummaryVerdict {
        var titleViolations = titleRuleViolations(title)
        var descriptionViolations = descriptionRuleViolations(description, title: title)
        descriptionViolations.append(contentsOf: tagEvaluator.bannedWordViolations(in: description))
        descriptionViolations.append(contentsOf: misnamingViolations(in: description))
        appendForbiddenTerms(expectation.forbiddenTerms, in: title, to: &titleViolations)
        appendForbiddenTerms(expectation.forbiddenTerms, in: description, to: &descriptionViolations)

        var tagExpectation = expectation.tags
        tagExpectation.forbiddenTerms = expectation.forbiddenTerms
        let tagResult = tagEvaluator.evaluate(tags: tags, title: title, expectation: tagExpectation)
        let tagRuleViolations = tagResult.violations.filter { !$0.hasPrefix("matched ") }

        var conceptViolations: [String] = []
        var scores: [Double] = []

        scores.append(conceptScore(
            of: title, groups: expectation.titleConcepts, label: "title", into: &conceptViolations
        ))
        scores.append(conceptScore(
            of: description, groups: expectation.descriptionConcepts, label: "description", into: &conceptViolations
        ))
        let required = Double(max(tagResult.requiredGroupCount, 1))
        scores.append(min(Double(tagResult.matchedGroups.count) / required, 1))
        conceptViolations.append(contentsOf: tagResult.violations.filter { $0.hasPrefix("matched ") }.map { "tags: \($0)" })

        return TableSummaryVerdict(
            title: title,
            description: description,
            tags: tags,
            titleRuleViolations: titleViolations,
            descriptionRuleViolations: descriptionViolations,
            tagRuleViolations: tagRuleViolations,
            conceptViolations: conceptViolations,
            conceptScore: scores.reduce(0, +) / Double(scores.count)
        )
    }

    // MARK: - Title

    private func titleRuleViolations(_ title: String) -> [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["is empty"]
        }

        var violations: [String] = []
        if trimmed.count > maximumTitleCharacters {
            violations.append("is longer than \(maximumTitleCharacters) characters")
        }
        if trimmed.split(whereSeparator: \.isWhitespace).count > maximumTitleWords {
            violations.append("has more than \(maximumTitleWords) words")
        }
        if let last = trimmed.last, ".!?:;".contains(last) {
            violations.append("reads like a sentence")
        }

        let key = PdfTagEvaluator.normalized(trimmed)
        let leadingPart = key.prefix { $0 != ":" }.trimmingCharacters(in: .whitespaces)
        if genericTitles.contains(key) {
            violations.append("'\(trimmed)' is generic")
        } else if key.contains(":"), genericTitles.contains(leadingPart) || Self.hasFormLabel(leadingPart) {
            violations.append("'\(trimmed)' starts with a generic label")
        }
        return violations
    }

    // MARK: - Description

    private func descriptionRuleViolations(_ description: String, title: String) -> [String] {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ["is empty"]
        }

        var violations: [String] = []
        if trimmed.count < minimumDescriptionCharacters {
            violations.append("is shorter than \(minimumDescriptionCharacters) characters")
        }
        if trimmed.count > maximumDescriptionCharacters {
            violations.append("is longer than \(maximumDescriptionCharacters) characters")
        }
        let sentences = Self.sentenceCount(in: trimmed)
        if sentences > maximumDescriptionSentences {
            violations.append("has \(sentences) sentences, allowed are \(maximumDescriptionSentences)")
        }
        if PdfTagEvaluator.normalized(trimmed) == PdfTagEvaluator.normalized(title) {
            violations.append("repeats the title")
        }
        return violations
    }

    // MARK: - Helpers

    private func misnamingViolations(in text: String) -> [String] {
        let words = Set(text.split { !$0.isLetter }.map { PdfTagEvaluator.normalized(String($0)) })
        return misnamingWords
            .filter { words.contains(PdfTagEvaluator.normalized($0)) }
            .map { "calls the item a '\($0)'" }
    }

    private func appendForbiddenTerms(_ terms: [String], in text: String, to violations: inout [String]) {
        for term in terms where text.localizedStandardContains(term) {
            violations.append("contains forbidden term '\(term)'")
        }
    }

    private func conceptScore(
        of text: String,
        groups: [[String]],
        label: String,
        into violations: inout [String]
    ) -> Double {
        guard !groups.isEmpty else {
            return 1
        }
        let matched = groups.contains { group in group.contains { text.localizedStandardContains($0) } }
        if !matched {
            let wanted = groups.map { $0.joined(separator: "|") }.joined(separator: ", ")
            violations.append("\(label) matches none of the expected concepts: \(wanted)")
        }
        return matched ? 1 : 0
    }

    /// "RPG Loot Table: ..." and "RPG-Tabelle: ...": a label that names the form, not the content.
    private static func hasFormLabel(_ leadingPart: String) -> Bool {
        let words = leadingPart.split { !$0.isLetter }.map(String.init)
        return words.contains { ["table", "tabelle", "rpg"].contains($0) }
    }

    /// Counts sentences with the system tokenizer, which does not split on decimals or "1d6.".
    static func sentenceCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if !text[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                count += 1
            }
            return true
        }
        return count
    }
}

#endif
