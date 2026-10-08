// @copyright André Trettin

import Foundation
import Testing

@testable import PdfRPG

/// CODE_AUDIT_21 §5.17: a bookmark stores the label of its page; opening it read the label as a
/// page position.
@Suite("PDF bookmark page")
struct PdfBookmarkPageTests {
    /// Four pages of front matter, then the numbered pages.
    private let rulebook: [String?] = ["i", "ii", "iii", "iv", "1", "2", "3"]

    @Test("A label is looked up, not read as a position")
    func labelIsLookedUp() {
        // Page "2" is the sixth page, not the second.
        #expect(PdfBookmarkPage.pageIndex(label: "2", in: rulebook, matchesContent: { _ in false }) == 5)
        #expect(PdfBookmarkPage.pageIndex(label: "iii", in: rulebook, matchesContent: { _ in false }) == 2)
    }

    @Test("A repeated label goes to the page that still holds the bookmarked text")
    func repeatedLabelUsesContent() {
        let chapters: [String?] = ["1", "2", "1", "2"]
        #expect(PdfBookmarkPage.pageIndex(label: "2", in: chapters, matchesContent: { $0 == 3 }) == 3)
        // No page matches the text any more: the first with the label.
        #expect(PdfBookmarkPage.pageIndex(label: "2", in: chapters, matchesContent: { _ in false }) == 1)
    }

    @Test("Without a page of that label a number is the page's position")
    func numberFallsBackToPosition() {
        let unlabelled: [String?] = [nil, nil, nil]
        #expect(PdfBookmarkPage.pageIndex(label: "2", in: unlabelled, matchesContent: { _ in false }) == 1)
        #expect(PdfBookmarkPage.pageIndex(label: "9", in: unlabelled, matchesContent: { _ in false }) == nil)
        #expect(PdfBookmarkPage.pageIndex(label: "-", in: unlabelled, matchesContent: { _ in false }) == nil)
    }
}
