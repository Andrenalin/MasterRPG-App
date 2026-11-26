// @copyright André Trettin

#if !os(tvOS)

import CoreGraphics
import CoreRPG
import Foundation
import GeneratorRPG
import Testing

@testable import PdfRPG

/// The batch "Extract Information" adds the generated sections as bookmarks, but never twice:
/// a section whose name and page match an existing bookmark is skipped (decision of 2026-11-26).
@Suite("PDF bookmark merge")
@MainActor
struct PdfBookmarkMergeTests {
    private func bookmark(_ name: String, page: String) -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: name, content: "", pageNumber: page, bounds: .zero)
    }

    @Test("A section matching an existing bookmark by name and page is skipped")
    func existingBookmarkIsSkipped() {
        let entries = PdfBookmarkMerge.newEntries(
            for: [
                PdfSection(heading: " chapter one ", summary: "Start", pageNumber: 3),
                PdfSection(heading: "Chapter One", summary: "Same name, other page", pageNumber: 9),
                PdfSection(heading: "Appendix", summary: "Reference", pageNumber: nil)
            ],
            existing: [bookmark("Chapter One", page: "3")],
            pageLabel: { _ in nil }
        )
        #expect(entries.map(\.name) == ["Chapter One", "Appendix"])
        #expect(entries.map(\.pageLabel) == ["9", ""])
    }

    @Test("Duplicate and empty sections in one result add one bookmark")
    func duplicateAndEmptySectionsAreDropped() {
        let entries = PdfBookmarkMerge.newEntries(
            for: [
                PdfSection(heading: "Maps", summary: "A", pageNumber: 2),
                PdfSection(heading: "maps", summary: "B", pageNumber: 2),
                PdfSection(heading: "   ", summary: "No name", pageNumber: 4)
            ],
            existing: [],
            pageLabel: { _ in nil }
        )
        #expect(entries.map(\.name) == ["Maps"])
        #expect(entries.first?.content == "A")
    }

    @Test("Pages are stored as page labels, so the duplicate check uses labels too")
    func pageLabelsAreUsed() {
        let entries = PdfBookmarkMerge.newEntries(
            for: [
                PdfSection(heading: "Intro", summary: "", pageNumber: 1),
                PdfSection(heading: "Rules", summary: "", pageNumber: 5)
            ],
            existing: [bookmark("Intro", page: "i")],
            pageLabel: { $0 == 1 ? "i" : "\($0 - 1)" }
        )
        #expect(entries.map(\.name) == ["Rules"])
        #expect(entries.map(\.pageLabel) == ["4"])
    }

    @Test("Generated text is bounded")
    func generatedTextIsBounded() {
        let entries = PdfBookmarkMerge.newEntries(
            for: [PdfSection(heading: String(repeating: "H", count: 300), summary: String(repeating: "S", count: 900), pageNumber: 1)],
            existing: [],
            pageLabel: { _ in nil }
        )
        #expect(entries.first?.name.count == PdfBookmarkMerge.maximumNameLength)
        #expect(entries.first?.content.count == PdfBookmarkMerge.maximumContentLength)
    }

    @Test("Running the batch twice adds the bookmarks once and keeps the existing ones")
    func editControllerAddsOnlyNewBookmarks() {
        let root = PdfRootModel.testRoot()
        let itemId = UUID()
        let own = bookmark("My Note", page: "2")
        root.itemController.replace(model: PdfModel(id: itemId, name: "Rulebook", entries: [own]), isInsert: true)
        let sections = [
            PdfSection(heading: "Combat", summary: "Fighting", pageNumber: 10),
            PdfSection(heading: "Magic", summary: "Spells", pageNumber: 20)
        ]

        let first = root.editController.addExtractedBookmarks(sections, to: itemId) { _ in nil }
        let second = root.editController.addExtractedBookmarks(sections, to: itemId) { _ in nil }

        #expect(first == 2)
        #expect(second == 0)
        let entries = root.itemController.itemOrEmpty(for: itemId).entries
        #expect(entries.map(\.name) == ["My Note", "Combat", "Magic"])
        #expect(entries.first == own)
    }

    @Test("The PDF module offers the batch extraction")
    func viewControllerOffersBatchExtraction() {
        let root = PdfRootModel.testRoot()
        let sut = ViewController()
        #expect(sut.supportsBatchExtraction)
        #expect(sut.batchExtractionView(itemController: root.itemController, editController: root.editController, ids: [UUID()]) != nil)
    }
}

#endif
