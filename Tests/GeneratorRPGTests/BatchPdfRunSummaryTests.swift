// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

/// The result line of the PDF batch counts an item as changed when its name, description or
/// tags changed, or when bookmarks were added.
@Suite("Batch PDF run summary")
struct BatchPdfRunSummaryTests {
    @Test("Counts each kind of change")
    func countsChanges() {
        var summary = BatchPdfRunSummary()
        summary.record(.init(name: "Title", description: "Text", tags: ["A"]), addedBookmarks: 3)
        summary.record(.init(name: nil, description: "Text", tags: nil), addedBookmarks: 0)

        #expect(summary == BatchPdfRunSummary(changedItems: 2, filledNames: 1, replacedDescriptions: 2, replacedTags: 1, addedBookmarks: 3))
    }

    @Test("Bookmarks alone change an item, nothing at all does not")
    func bookmarksAloneCount() {
        var summary = BatchPdfRunSummary()
        summary.record(.init(), addedBookmarks: 2)
        summary.record(.init(), addedBookmarks: 0)

        #expect(summary.changedItems == 1)
        #expect(summary.addedBookmarks == 2)
    }
}

#endif
