// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import PDFKit

/// Finds the page a bookmark points at.
///
/// A bookmark stores the label of its page (what the page is called in the document: "iv",
/// "12", "A-3"), which is also what the bookmark list shows. Opening one used to read that label
/// as a number and take it as the page's position, so in a rulebook with roman-numbered front
/// matter or offset numbering the bookmark opened another page, or none.
/// See CODE_AUDIT_21 §5.17.
enum PdfBookmarkPage {
    @MainActor
    static func page(for entry: PdfEntryModel, in document: PDFDocument) -> PDFPage? {
        let labels = (0..<document.pageCount).map { document.page(at: $0)?.label }
        guard let index = pageIndex(
            label: entry.pageLabel,
            in: labels,
            matchesContent: { index in
                guard let page = document.page(at: index) else { return false }
                return selectionMatches(entry, on: page)
            }
        ) else { return nil }
        return document.page(at: index)
    }

    /// The position of the page labelled `label`. Labels can repeat (every chapter starting at
    /// "1"): the page whose stored selection still holds the bookmarked text is taken then,
    /// else the first with the label. Without any page of that label, a number is read as the
    /// page's position, which is what bookmarks of a document without labels have always meant.
    static func pageIndex(label: String, in labels: [String?], matchesContent: (Int) -> Bool) -> Int? {
        let candidates = labels.indices.filter { labels[$0] == label }
        if candidates.count > 1, let match = candidates.first(where: matchesContent) {
            return match
        }
        if let first = candidates.first {
            return first
        }
        guard let number = Int(label), labels.indices.contains(number - 1) else { return nil }
        return number - 1
    }

    @MainActor
    private static func selectionMatches(_ entry: PdfEntryModel, on page: PDFPage) -> Bool {
        let bookmarked = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bookmarked.isEmpty,
              let text = page.selection(for: entry.bounds)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return false }
        return text.hasPrefix(bookmarked) || bookmarked.hasPrefix(text)
    }
}
#endif
