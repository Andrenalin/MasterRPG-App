// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import GeneratorRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import CharacterRPG
import Testing

@testable import AdventureRPG

@MainActor
struct EditControllerTests {
    @Test("Generated content is inserted after its focused entry")
    func insertGeneratedEntryAtFocus() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        let sut = root.editController
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let anchorId = try #require(root.itemController.itemOrEmpty(for: itemId).entries.first?.id)

        // When
        let insertedId = try #require(
            sut.insertEntry(
                itemId: itemId,
                name: "Generated Scene",
                content: "A newly generated complication.",
                position: .after(anchorId)
            )
        )
        let updated = root.itemController.itemOrEmpty(for: itemId)
        let anchorIndex = try #require(updated.entries.firstIndex { $0.id == anchorId })

        // Then
        #expect(updated.entries[anchorIndex + 1].id == insertedId)
        #expect(updated.entries[anchorIndex + 1].name == "Generated Scene")
        #expect(updated.entries[anchorIndex + 1].content == "A newly generated complication.")
        #expect(
            sut.insertEntry(
                itemId: UUID(),
                name: "Missing",
                content: "Should not be inserted",
                position: .end
            ) == nil
        )
    }

    @Test func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController
        let itemId = root.itemController.itemDataModel.items[0]

        sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .adventure))
        let item = root.itemController.itemOrEmpty(for: itemId).copy()
        let originalEntries = item.entries
        
        item.entries[0].content = "New Content"
        var result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)
        
        let savedItem = root.itemController.itemOrEmpty(for: itemId)

        #expect(savedItem.entries[0].id == originalEntries[0].id)
        #expect(savedItem.entries[0].content == "New Content")
        
        let newEntry = AdventureEntryModel(id: UUID(), name: "Newbee", content: "Super")
        item.entries.append(newEntry)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            #expect(savedItem.entries[index].id == entry.id)
        }
        #expect(savedItem.entries.last?.id == newEntry.id)
        
        let middleEntry = AdventureEntryModel(id: UUID(), name: "Middle", content: "Super")
        item.entries.insert(middleEntry, at: 4)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            if index < 4 {
                #expect(savedItem.entries[index].id == entry.id)
            } else if index == 4 {
                #expect(savedItem.entries[4].id == middleEntry.id)
            } else {
                #expect(savedItem.entries[index + 1].id == entry.id)
            }
        }
    }

    @Test func routesMediaExtractionAndPhotoCollection() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let itemId = UUID()
        let entryId = UUID()
        let diceId = UUID()
        let photoId = UUID()
        let entry = AdventureEntryModel(id: entryId, name: "Scene", content: "Old content")
        let adventure = AdventureModel(id: itemId, name: "Old Adventure", description: "Old description", tags: ["old"], entries: [entry])
        root.itemController.replace(model: adventure, isInsert: true)

        _ = sut.itemControllable
        _ = sut.fileUrlDataController
        _ = sut.linkRegisterController
        _ = sut.adventureEditModel
        _ = sut.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .adventure))
        _ = sut.quickEditorDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .adventure))

        #expect(sut.canAddLink(module: .photo, entryId: entryId))
        #expect(sut.linkModules == [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .rule, .space, .table, .weather])

        sut.add(diceId: diceId, itemId: itemId)
        sut.add(photoId: photoId, itemId: itemId)
        var updated = root.itemController.itemOrEmpty(for: itemId)
        #expect(updated.photoId == photoId)

        sut.collectPhotos(itemId: itemId, entryId: entryId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entryId].name == "Collection")

        let created = sut.create(name: "Created", content: "Created content")
        #expect(created.name == "Created")
        #expect(created.content == "Created content")

        let merged = sut.merge(itemId: itemId, entries: [
            AdventureEntryModel(id: UUID(), name: "Scene", content: "Updated content"),
            created
        ])
        #expect(merged.map(\.name) == ["Scene", "Created"])
        #expect(merged.first?.content == "Updated content")

        #expect(sut.merge(itemId: UUID(), entries: [created]).map(\.name) == ["Created"])
        #expect(sut.merge(itemId: UUID(), entries: [created], recoverEntries: nil).isEmpty)
        #expect(sut.merge(itemId: itemId, entries: [created], recoverEntries: []).isEmpty)

        sut.applyExtractedContent(
            TableSummaryAnalysis(title: "Extracted Adventure", description: "Extracted description", tags: ["dungeon", "mystery"]),
            to: itemId,
            selection: TextSummaryPropertySelection()
        )

        updated = root.itemController.itemOrEmpty(for: itemId)
        #expect(updated.name == "Extracted Adventure")
        #expect(updated.description == "Extracted description")
        #expect(updated.tags.sorted() == ["dungeon", "mystery"])

        sut.applyExtractedContent(
            TableSummaryAnalysis(title: "Skipped", description: "Skipped", tags: ["skip"]),
            to: itemId,
            selection: TextSummaryPropertySelection(applyTitle: false, applyDescription: false, applyTags: false)
        )
        #expect(root.itemController.itemOrEmpty(for: itemId).name == "Extracted Adventure")

    }
}
