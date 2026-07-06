// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import GeneratorRPG
import Testing

@testable import PdfRPG

@MainActor
struct EditControllerTests {
    @Test func bookmarksMergesRoutesAndExtractedContent() {
        let root = PdfRootModel.testRoot()
        let sut = root.editController
        let itemId = UUID()
        let originalEntry = PdfEntryModel(id: UUID(), name: "Old", content: "Old text", pageNumber: "1", bounds: .zero)
        let pdf = PdfModel(id: itemId, name: "Original PDF", description: "Original description", entries: [originalEntry])
        root.itemController.replace(model: pdf, isInsert: true)

        _ = sut.itemControllable
        _ = sut.fileUrlDataController
        _ = sut.linkRegisterController
        _ = sut.linkModules
        _ = sut.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .pdf))
        _ = sut.quickEditorDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .pdf))

        let created = sut.create(name: "Created", content: "Created text")
        #expect(created.name == "Created")
        #expect(created.content == "Created text")

        let bookmark = sut.createBookmark(
            itemId: UUID(),
            content: "Bookmark summary text",
            page: "7",
            bounds: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        #expect(bookmark.name == "Bookmark")
        #expect(bookmark.pageLabel == "7")
        #expect(bookmark.bounds.origin.x == 1)

        let unnamed = sut.createBookmark(itemId: UUID(), content: "", page: "8", bounds: .zero)
        #expect(!unnamed.name.isEmpty)

        sut.addBookmark(itemId: itemId, entry: bookmark)
        #expect(root.itemController.itemOrEmpty(for: itemId).entries.map(\.name).contains("Bookmark"))

        let merged = sut.merge(itemId: itemId, entries: [
            PdfEntryModel(id: UUID(), name: "Old", content: "Updated text", pageNumber: "2", bounds: .zero),
            created
        ])
        #expect(merged.count == 2)
        #expect(merged.first?.content == "Updated text")

        let blockedRemovalRows = sut.merge(itemId: itemId, entries: [created], recoverEntries: nil)
        #expect(blockedRemovalRows.isEmpty)
        let removedWithoutLinks = sut.merge(itemId: itemId, entries: [created], recoverEntries: [])
        #expect(removedWithoutLinks.isEmpty)

        let content = PdfSummaryAnalysis(
            title: "Extracted Title",
            summary: "Extracted summary",
            tags: ["rules", "magic"],
            sections: [
                PdfSection(heading: "Chapter One", summary: "A beginning", pageNumber: 3),
                PdfSection(heading: "Appendix", summary: "Reference", pageNumber: nil)
            ]
        )
        sut.applyExtractedContent(content, to: itemId, selection: PdfPropertySelection())

        let updated = root.itemController.itemOrEmpty(for: itemId)
        #expect(updated.name == "Extracted Title")
        #expect(updated.description == "Extracted summary")
        #expect(updated.tags.sorted() == ["magic", "rules"])
        #expect(Array(updated.entries.map(\.name).suffix(2)) == ["Chapter One", "Appendix"])
        #expect(Array(updated.entries.map(\.pageLabel).suffix(2)) == ["3", ""])

        let skippedContent = PdfSummaryAnalysis(title: "Skipped", summary: "Skipped", tags: ["skip"], sections: [PdfSection(heading: "Skipped", summary: "Skipped")])
        sut.applyExtractedContent(
            skippedContent,
            to: itemId,
            selection: PdfPropertySelection(applyTitle: false, applyDescription: false, applyTags: false, applySections: false)
        )
        #expect(root.itemController.itemOrEmpty(for: itemId).name == "Extracted Title")

        #expect(sut.merge(itemId: UUID(), entries: [created]).count == 1)
        #expect(sut.merge(itemId: UUID(), entries: [created], recoverEntries: nil).isEmpty)
    }
}
