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
    }

    /// Non-empty page texts of the first `pageLimit` pages, in page order.
    @concurrent
    static func pages(of document: ReadOnlyDocument, pageLimit: Int) async throws -> [Page] {
        var pages: [Page] = []
        pages.reserveCapacity(pageLimit)
        for pageIndex in 0..<pageLimit {
            try Task.checkCancellation()
            guard let page = document.document.page(at: pageIndex),
                  let text = page.string,
                  !text.isEmpty else {
                continue
            }
            pages.append(Page(pageNumber: pageIndex + 1, text: text))
        }
        return pages
    }
}
