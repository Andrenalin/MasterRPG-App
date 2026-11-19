// @copyright André Trettin

import Foundation
import Testing

@testable import PdfRPG

#if !os(tvOS)
import PDFKit

/// CODE_AUDIT_TestGaps §5.15: the in-document search state of the PDF viewer: the request
/// counter that starts a find, the match cursor and its bounds, and the end of a search.
@MainActor
@Suite("Pdf search model")
struct PdfSearchModelTests {
    private func match(_ page: PDFPage? = nil) -> PDFSelection {
        PDFSelection(document: PDFDocument())
    }

    private func model(matchCount: Int) -> PdfSearchModel {
        let model = PdfSearchModel()
        model.matches = (0..<matchCount).map { _ in match() }
        return model
    }

    @Test("Starting a search stores the term, restarts the find and counts one request")
    func searchCountsRequests() {
        let model = PdfSearchModel()
        model.pdfSearching = true

        model.search(for: "dragon")

        #expect(model.searchText == "dragon")
        #expect(!model.pdfSearching, "a new find may begin")
        #expect(model.searchRequest == 1)

        model.search(for: "dragon")
        #expect(model.searchRequest == 2, "the same term again is a new request")
    }

    @Test("Repeating the displayed term starts the search again")
    func resetSearchRepeatsTheDisplayedTerm() {
        let model = PdfSearchModel()
        model.displaySearchText = "tavern"

        model.resetSearch()

        #expect(model.searchText == "tavern")
        #expect(model.searchRequest == 1)
    }

    @Test("The next and previous buttons are disabled at the ends and without matches")
    func buttonBounds() {
        let none = model(matchCount: 0)
        #expect(none.disabledNext())
        #expect(none.disabledPrev())

        let one = model(matchCount: 1)
        #expect(one.disabledNext())
        #expect(one.disabledPrev())

        let three = model(matchCount: 3)
        #expect(!three.disabledNext())
        #expect(three.disabledPrev(), "at the first match")
        three.currentIndex = 2
        #expect(three.disabledNext(), "at the last match")
        #expect(!three.disabledPrev())
    }

    @Test("Stepping moves through the matches, tells the viewer, and stops at the ends")
    func stepping() {
        let model = model(matchCount: 3)
        var shown: [Int] = []
        model.setSearchMatch = { _, index in shown.append(index) }

        model.previousMatch()
        #expect(model.currentIndex == 0 && shown.isEmpty, "nothing before the first match")
        model.nextMatch()
        model.nextMatch()
        model.nextMatch()
        #expect(model.currentIndex == 2)
        #expect(shown == [1, 2], "no move, and no message, past the last match")
        model.previousMatch()
        #expect(model.currentIndex == 1)
        #expect(shown == [1, 2, 1])
    }

    @Test("Ending the search drops the matches and the position")
    func endSearch() {
        let model = model(matchCount: 4)
        model.currentIndex = 3

        model.endSearch()

        #expect(model.matches.isEmpty)
        #expect(model.currentIndex == 0)
        #expect(model.disabledNext() && model.disabledPrev())
    }

    @Test("A find does not begin without a term or a viewer")
    func findNeedsTermAndViewer() {
        let model = PdfSearchModel()

        model.beginFindIfNeeded()
        #expect(!model.pdfSearching)

        model.search(for: "orc")
        model.beginFindIfNeeded()
        #expect(!model.pdfSearching, "no PDFView is attached")
        #expect(!model.isSearching)
    }

    @Test("The viewer is rebuilt for a replaced file: the load key follows the version")
    func loadKeyFollowsTheVersion() {
        let id = UUID()

        #expect(PdfViewerLoadKey(id: id, version: 1) == PdfViewerLoadKey(id: id, version: 1))
        #expect(PdfViewerLoadKey(id: id, version: 1) != PdfViewerLoadKey(id: id, version: 2))
        #expect(PdfViewerLoadKey(id: id, version: 1) != PdfViewerLoadKey(id: UUID(), version: 1))
    }
}
#endif
