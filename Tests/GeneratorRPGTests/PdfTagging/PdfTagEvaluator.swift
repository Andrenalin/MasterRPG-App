// @copyright André Trettin

#if !os(tvOS)

import Foundation

/// What a good tag set for one PDF looks like. Content expectations are *concept groups*: a group
/// is matched when any of its terms appears in any tag, so "dungeon" and "Verlies" can stand for
/// the same idea and the model is not pinned to one wording.
struct PdfTagExpectation: Codable, Sendable, Equatable {
    /// Each inner array is one concept; a tag containing any of its terms matches the concept.
    var conceptGroups: [[String]]
    /// How many of `conceptGroups` must be matched. `nil` means all of them.
    var minimumMatchedGroups: Int?
    /// Terms no tag may contain, e.g. English words for a German document.
    var forbiddenTerms: [String] = []

    init(conceptGroups: [[String]], minimumMatchedGroups: Int? = nil, forbiddenTerms: [String] = []) {
        self.conceptGroups = conceptGroups
        self.minimumMatchedGroups = minimumMatchedGroups
        self.forbiddenTerms = forbiddenTerms
    }

    var requiredGroupCount: Int {
        min(minimumMatchedGroups ?? conceptGroups.count, conceptGroups.count)
    }
}

/// The result of checking one generated analysis against the rules and the expectation.
struct PdfTagEvaluation: Sendable, Equatable {
    let tags: [String]
    let title: String
    let violations: [String]
    let matchedGroups: [Int]
    let requiredGroupCount: Int
    let groupCount: Int

    var passed: Bool { violations.isEmpty }

    /// Fraction of expected concepts that were found, for the report.
    var recall: Double {
        groupCount == 0 ? 1 : Double(matchedGroups.count) / Double(groupCount)
    }
}

/// Scores the tags of one `PdfSummaryAnalysis`. Pure, so the rules themselves are unit-tested
/// without Apple Intelligence.
struct PdfTagEvaluator: Sendable {
    /// Mirrors `@Guide(.count(3...5))` on `PdfSummaryAnalysis.tags`; the tag UI cannot show more.
    var allowedCount = 3...5
    var maximumWordsPerTag = 4
    var maximumCharactersPerTag = 40
    /// Words that describe the file, not the game.
    var noiseTags: Set<String> = ["pdf", "document", "file", "text", "summary", "page", "pages"]
    /// Generic words that fit every RPG document, or that the analyzer prompt itself used as
    /// category labels ("genre, setting, system"). Such a tag says nothing about the document, and
    /// the model copying them wastes one of the few tag slots, so a run fails.
    var genericTags: Set<String> = [
        "genre", "setting", "system", "mechanics", "type", "document type", "tags", "tag",
        "sections", "chapters", "rpg", "ttrpg", "role-playing game", "roleplaying game",
        "role-playing", "roleplaying", "tabletop", "tabletop rpg", "rollenspiel", "pen & paper"
    ]

    func evaluate(tags: [String], title: String, expectation: PdfTagExpectation) -> PdfTagEvaluation {
        var violations: [String] = []

        if !allowedCount.contains(tags.count) {
            violations.append("tag count \(tags.count) is outside \(allowedCount)")
        }

        var seen = Set<String>()
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalized(trimmed)

            if trimmed.isEmpty {
                violations.append("empty tag")
                continue
            }
            if !seen.insert(key).inserted {
                violations.append("duplicate tag '\(trimmed)'")
            }
            if trimmed.count > maximumCharactersPerTag {
                violations.append("tag '\(trimmed)' is longer than \(maximumCharactersPerTag) characters")
            }
            if trimmed.split(whereSeparator: \.isWhitespace).count > maximumWordsPerTag {
                violations.append("tag '\(trimmed)' has more than \(maximumWordsPerTag) words")
            }
            if let last = trimmed.last, ".!?:;".contains(last) {
                violations.append("tag '\(trimmed)' reads like a sentence")
            }
            if noiseTags.contains(key) {
                violations.append("tag '\(trimmed)' describes the file, not the game")
            }
            if trimmed.contains(":") {
                violations.append("tag '\(trimmed)' uses a 'label: value' form")
            }
            // "Setting (1893, village)" and "Genre: Horror" start with a generic label too.
            let leadingPart = key.prefix { $0 != ":" && $0 != "(" }
                .trimmingCharacters(in: .whitespaces)
            if genericTags.contains(key) || genericTags.contains(leadingPart) {
                violations.append("tag '\(trimmed)' is generic or a prompt label")
            }
            if !Self.normalized(title).isEmpty, key == Self.normalized(title) {
                violations.append("tag '\(trimmed)' repeats the title")
            }
            for term in expectation.forbiddenTerms where trimmed.localizedStandardContains(term) {
                violations.append("tag '\(trimmed)' contains forbidden term '\(term)'")
            }
        }

        let matched = expectation.conceptGroups.indices.filter { index in
            expectation.conceptGroups[index].contains { term in
                tags.contains { $0.localizedStandardContains(term) }
            }
        }
        if matched.count < expectation.requiredGroupCount {
            let missing = expectation.conceptGroups.indices
                .filter { !matched.contains($0) }
                .map { expectation.conceptGroups[$0].joined(separator: "|") }
            violations.append(
                "matched \(matched.count) of \(expectation.requiredGroupCount) required concepts; missing: \(missing.joined(separator: ", "))"
            )
        }

        return PdfTagEvaluation(
            tags: tags,
            title: title,
            violations: violations,
            matchedGroups: matched,
            requiredGroupCount: expectation.requiredGroupCount,
            groupCount: expectation.conceptGroups.count
        )
    }

    /// Case- and diacritic-insensitive key, so "Dungeon" and "dungeon " count as the same tag.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

#endif
