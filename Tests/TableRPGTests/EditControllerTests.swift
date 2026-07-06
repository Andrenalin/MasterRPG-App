// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import GeneratorRPG
import PdfRPG
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct EditControllerTests {
    @Test @MainActor func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = root.itemController.itemDataModel.items[0]
        let sut = root.editController

        sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .table))
        let item = root.itemController.itemOrEmpty(for: itemId).copy()
        let originalEntries = item.entries

        item.entries[0].content = "New Content"
        var result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        let savedItem = root.itemController.itemOrEmpty(for: itemId)
        #expect(savedItem.entries[0].id == originalEntries[0].id)
        #expect(savedItem.entries[0].content == "New Content")

        let newEntry = TableEntryModel(id: UUID(), name: "Newbee", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.append(newEntry)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
            #expect(savedItem.entries[index].id == entry.id)
        }
        #expect(savedItem.entries.last?.id == newEntry.id)

        let middleEntry = TableEntryModel(id: UUID(), name: "Middle", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.insert(middleEntry, at: 4)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
            if index < 4 {
                #expect(savedItem.entries[index].id == entry.id)
            } else if index == 4 {
                #expect(savedItem.entries[4].id == middleEntry.id)
            } else {
                #expect(savedItem.entries[index + 1].id == entry.id)
            }
        }
    }

    @Test func routesDiceAndExtractedContent() {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let root = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let sut = root.editController
        let itemId = UUID()
        let diceId = UUID()
        let table = TableModel(id: itemId, name: "Old Table", description: "Old description", tags: ["old"], entries: [])
        root.itemController.replace(model: table, isInsert: true)

        _ = sut.itemControllable
        _ = sut.fileUrlDataController
        _ = sut.linkRegisterController
        _ = sut.tableEditModel
        _ = sut.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .table))
        _ = sut.quickEditorDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .table))

        #expect(sut.linkModules == [.dice, .pdf, .table])
        #expect(sut.canAddLink(module: .table, entryId: nil))
        #expect(sut.canAddLink(module: .dice, entryId: UUID()))
        #expect(sut.canAddLink(module: .pdf, entryId: nil))
        #expect(!sut.canAddLink(module: .photo, entryId: nil))

        sut.add(diceId: diceId, itemId: itemId)
        #expect(root.itemController.itemOrEmpty(for: itemId).diceId == diceId)

        let created = sut.create(name: "Created", content: "Content")
        #expect(created.name == "Created")
        #expect(created.content == "Content")

        #expect(sut.merge(itemId: UUID(), entries: [created]).map(\.name) == ["Created"])
        #expect(sut.merge(itemId: UUID(), entries: [created], recoverEntries: nil).isEmpty)

        sut.applyExtractedContent(
            TableSummaryAnalysis(title: "Extracted Table", description: "Extracted description", tags: ["encounter", "loot"]),
            to: itemId,
            selection: TextSummaryPropertySelection()
        )

        let updated = root.itemController.itemOrEmpty(for: itemId)
        #expect(updated.name == "Extracted Table")
        #expect(updated.description == "Extracted description")
        #expect(updated.tags.sorted() == ["encounter", "loot"])

        sut.applyExtractedContent(
            TableSummaryAnalysis(title: "Skipped", description: "Skipped", tags: ["skip"]),
            to: itemId,
            selection: TextSummaryPropertySelection(applyTitle: false, applyDescription: false, applyTags: false)
        )
        #expect(root.itemController.itemOrEmpty(for: itemId).name == "Extracted Table")
    }
}
