// @copyright André Trettin

import Foundation
import PDFKit

/// Reads PDF page text off the caller's actor.
///
/// The analyzers are nonisolated async functions, which run on their (main-actor) caller's
/// executor, so `page.string` for up to 20 pages used to run on the main actor and hitch the
/// UI before generation even started. See CODE_AUDIT_18 §3.5.
enum PdfPageTextReader {
    /// `PDFDocument` is not `Sendable`. Reading page text is safe here because the analysis
    /// only reads the document, and nothing mutates it while an analysis runs.
    struct ReadOnlyDocument: @unchecked Sendable {
        let document: PDFDocument
    }

    struct Page: Sendable {
        let pageNumber: Int
        let text: String
        /// The page had more characters than `maximumCharactersPerPage`; `text` is its start.
        var wasCapped = false
    }

    /// Non-empty page texts of the first `pageLimit` pages, in page order.
    ///
    /// `maximumCharactersPerPage` cuts each page right after it is read, so a page of a scanned
    /// book does not stay in memory in full until the limiter trims it; `stopAfterCharacters`
    /// ends the read once that many characters are collected (the analyzers cap the combined
    /// text anyway). See CODE_AUDIT_26 §7.62.
    @concurrent
    static func pages(
        of document: ReadOnlyDocument,
        pageLimit: Int,
        maximumCharactersPerPage: Int? = nil,
        stopAfterCharacters: Int? = nil
    ) async throws -> [Page] {
        var pages: [Page] = []
        pages.reserveCapacity(pageLimit)
        var collected = 0
        for pageIndex in 0..<pageLimit {
            try Task.checkCancellation()
            guard let page = document.document.page(at: pageIndex),
                  var text = page.string,
                  !text.isEmpty else {
                continue
            }
            var wasCapped = false
            if let maximumCharactersPerPage, text.count > maximumCharactersPerPage {
                text = String(text.prefix(maximumCharactersPerPage))
                wasCapped = true
            }
            collected += text.count
            pages.append(Page(pageNumber: pageIndex + 1, text: text, wasCapped: wasCapped))
            if let stopAfterCharacters, collected >= stopAfterCharacters { break }
        }
        return pages
    }
}
