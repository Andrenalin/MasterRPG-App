// @copyright André Trettin

import Foundation

/// Cleans PDF page text before `PdfSummaryAnalyzer` sends it to the on-device model.
///
/// The analysis only sends about 7,000 characters. Extracted PDF text spends much of that on
/// noise: object replacement characters for images and form fields, soft hyphens, words split at
/// the end of a line, the number grids of character sheets, and the imprint, credits and license
/// pages at the start of a book. The model then sees little of what the document is about.
enum PdfAnalysisTextCleaner {

    // MARK: - Page text

    /// `text` without invisible characters, line-break hyphens, lines without a letter, dot
    /// leaders and repeated whitespace. Empty when nothing readable is left.
    static func cleaned(_ text: String) -> String {
        var text = text
        text.unicodeScalars.removeAll { removedScalars.contains($0) }

        var lines: [String] = []
        var previousWasBlank = true
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = normalizedLine(rawLine)
            if line.isEmpty {
                // A run of blank lines becomes one.
                if !previousWasBlank {
                    lines.append("")
                    previousWasBlank = true
                }
                continue
            }
            // Page numbers, number grids, rules and bullets alone on a line.
            guard line.contains(where: \.isLetter) else { continue }

            if !previousWasBlank, let last = lines.last, let joined = joinedHyphenation(last, line) {
                lines[lines.count - 1] = joined
            } else {
                lines.append(line)
            }
            previousWasBlank = false
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// U+FFFC object replacement (images, form fields), U+00AD soft hyphen, zero-width spaces
    /// and the byte order mark.
    private static let removedScalars: Set<Unicode.Scalar> = ["\u{FFFC}", "\u{00AD}", "\u{200B}", "\u{FEFF}"]

    /// Leader characters that table-of-contents lines repeat ("Pirat ......46").
    private static let leaderCharacters: Set<Character> = [".", "•", "·", "…", "_"]

    /// The line with runs of whitespace collapsed to one space, dot leaders replaced by a space,
    /// and trimmed.
    private static func normalizedLine(_ line: Substring) -> String {
        var result = ""
        result.reserveCapacity(line.count)
        var pendingSpace = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character.isWhitespace {
                pendingSpace = true
                index = line.index(after: index)
                continue
            }
            if leaderCharacters.contains(character) {
                var end = index
                var count = 0
                while end < line.endIndex, leaderCharacters.contains(line[end]) {
                    count += 1
                    end = line.index(after: end)
                }
                if count >= 3 {
                    pendingSpace = true
                    index = end
                    continue
                }
            }
            if pendingSpace, !result.isEmpty {
                result.append(" ")
            }
            pendingSpace = false
            result.append(character)
            index = line.index(after: index)
        }
        return result
    }

    /// "gleichnami-" + "gen ..." becomes "gleichnamigen ...", when the next line starts with a
    /// lowercase letter. "Volks-" + "und Klassenbonus" keeps the hyphen ("Volks- und"), and
    /// "Rhein-" + "Ruhr" stays two lines, since the hyphen may be part of the word.
    private static func joinedHyphenation(_ previous: String, _ next: String) -> String? {
        guard previous.hasSuffix("-"),
              previous.dropLast().last?.isLetter == true,
              let first = next.first, first.isLowercase else {
            return nil
        }
        let firstWord = next.prefix { $0.isLetter }.lowercased()
        if conjunctions.contains(firstWord) {
            return previous + " " + next
        }
        return String(previous.dropLast()) + next
    }

    /// Words after a suspended hyphen ("Kultur- und Klassenbonus").
    private static let conjunctions: Set<String> = ["und", "oder", "bzw", "sowie", "als", "and", "or", "to"]

    // MARK: - Boilerplate pages

    /// Whether the cleaned page text is an imprint, credits, license or copyright page.
    ///
    /// A short page needs two different markers, a long page four, so a content page with a
    /// credits line or a license footer is kept.
    static func isBoilerplate(_ cleanedText: String) -> Bool {
        // Markers can be split across lines ("Creative\nCommon").
        let lowered = cleanedText.lowercased().replacing("\n", with: " ")
        let hits = boilerplateMarkers.count(where: { lowered.contains($0) })
        return hits >= 4 || (hits >= 2 && cleanedText.count <= shortPageLength)
    }

    /// Pages up to this length count as boilerplate with two markers.
    private static let shortPageLength = 2_000

    private static let boilerplateMarkers: [String] = [
        "impressum",
        "autor:",
        "autoren:",
        "author:",
        "authors:",
        "herausgeber:",
        "lektorat",
        "redaktion:",
        "korrektorat",
        "covermotiv:",
        "covergestaltung:",
        "cover art:",
        "innenillustrationen:",
        "interior art:",
        "illustrationen:",
        "satz und layout:",
        "editor:",
        "editing:",
        "alle rechte vorbehalten",
        "all rights reserved",
        "creative common",
        "creativecommons.org",
        "copyright ©",
        "copyright (c)",
        "nachdruck, auch auszugsweise",
        "isbn"
    ]

    /// The pages without boilerplate pages, unless the document has nothing else: then every
    /// page stays, so an imprint is still analyzed rather than nothing.
    static func contentPages(_ pages: [PdfPageTextReader.Page]) -> [PdfPageTextReader.Page] {
        let content = pages.filter { !$0.isBoilerplate }
        return content.isEmpty ? pages : content
    }
}
