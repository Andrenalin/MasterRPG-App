// @copyright André Trettin

import Foundation

struct FoundationModelInputLimiter {
    struct PageText: Equatable, Sendable {
        let pageNumber: Int
        let text: String
        let wasTruncated: Bool
    }

    static let truncationMarker = "\n[Content truncated...]"

    static func limitedText(_ text: String, maxCharacters: Int) -> String {
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

        var combined = ""
        for (pageNumber, pageText) in pages.prefix(maxPages) where !pageText.isEmpty {
            let pageBlock = "--- Page \(pageNumber) ---\n\(pageText)\n\n"
            if combined.count + pageBlock.count > maxCharacters {
                let remaining = maxCharacters - combined.count
                if remaining > 0 {
                    combined += limitedText(pageBlock, maxCharacters: remaining)
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
