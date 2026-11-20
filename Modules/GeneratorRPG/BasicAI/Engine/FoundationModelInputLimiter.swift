// @copyright André Trettin

import Foundation

struct FoundationModelInputLimiter {
    struct PageText: Equatable, Sendable {
        let pageNumber: Int
        let text: String
        let wasTruncated: Bool
    }

    static let truncationMarker = "\n[Content truncated...]"

    /// `maxCharacters` is a budget for Latin text (about three characters per token). Chinese,
    /// Japanese and Korean text costs about one token per character, so the same character count
    /// would overflow the model's context window and the whole analysis would fail; the budget
    /// shrinks with the share of such characters. See CODE_AUDIT §5.20.
    static func scriptAdjustedLimit(for text: some StringProtocol, maxCharacters: Int) -> Int {
        let sample = text.prefix(sampleLength)
        guard !sample.isEmpty else { return maxCharacters }
        let dense = sample.unicodeScalars.count(where: isTokenDense)
        let fraction = Double(dense) / Double(sample.unicodeScalars.count)
        let factor = 1 - fraction * (2.0 / 3.0)
        return max(1, Int((Double(maxCharacters) * factor).rounded(.down)))
    }

    private static let sampleLength = 2_000

    private static func isTokenDense(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // Hiragana, Katakana
             0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0x20000...0x2A6DF: // CJK Extension B
            true
        default:
            false
        }
    }

    static func limitedText(_ text: String, maxCharacters: Int) -> String {
        cut(text, maxCharacters: scriptAdjustedLimit(for: text, maxCharacters: maxCharacters))
    }

    private static func cut(_ text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard text.count > maxCharacters else { return text }

        let marker = Self.truncationMarker
        guard maxCharacters > marker.count else {
            return String(marker.prefix(maxCharacters))
        }

        let contentLimit = max(0, maxCharacters - marker.count)
        return String(text.prefix(contentLimit)) + marker
    }

    static func limitedCombinedText(
        pages: [String],
        maxPages: Int,
        maxCharacters: Int
    ) -> String {
        limitedCombinedText(
            pages: pages.enumerated().map { (pageNumber: $0.offset + 1, text: $0.element) },
            maxPages: maxPages,
            maxCharacters: maxCharacters
        )
    }

    /// The same for pages that carry their own number. A document's empty pages are dropped
    /// before this, so the position in the list is not the page number: labelling by position
    /// told the model that page 7 was page 3 and made every section's page number wrong.
    /// See CODE_AUDIT_22 §5.8.
    static func limitedCombinedText(
        pages: [(pageNumber: Int, text: String)],
        maxPages: Int,
        maxCharacters: Int
    ) -> String {
        guard maxPages > 0, maxCharacters > 0 else { return "" }

        let maxCharacters = scriptAdjustedLimit(
            for: pages.prefix(maxPages).map { $0.text }.joined(separator: "\n"),
            maxCharacters: maxCharacters
        )
        var combined = ""
        for (pageNumber, pageText) in pages.prefix(maxPages) where !pageText.isEmpty {
            let pageBlock = "--- Page \(pageNumber) ---\n\(UntrustedPromptText.pageText(pageText))\n\n"
            if combined.count + pageBlock.count > maxCharacters {
                let remaining = maxCharacters - combined.count
                if remaining > 0 {
                    combined += cut(pageBlock, maxCharacters: remaining)
                } else if !combined.hasSuffix(truncationMarker) {
                    combined += truncationMarker
                }
                break
            }
            combined += pageBlock
        }

        return combined
    }

    static func limitedPageTexts(
        pages: [String],
        maxPages: Int,
        maxCharactersPerPage: Int
    ) -> [PageText] {
        guard maxPages > 0, maxCharactersPerPage > 0 else { return [] }

        return pages
            .prefix(maxPages)
            .enumerated()
            .compactMap { offset, text in
                guard !text.isEmpty else { return nil }
                let limited = limitedText(text, maxCharacters: maxCharactersPerPage)
                return PageText(
                    pageNumber: offset + 1,
                    text: limited,
                    wasTruncated: limited != text
                )
            }
    }
}
